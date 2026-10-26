import { execFileSync } from "node:child_process";

const endpoint = process.env.HOTKEYGO_WORKER_URL ?? "https://qwixit-api.levmisiliuk.workers.dev";
const resetSecret = process.env.HOTKEYGO_DEVELOPMENT_RESET_SECRET ?? readResetSecret();

if (!resetSecret) {
  fail(
    "HOTKEYGO_DEVELOPMENT_RESET_SECRET is missing. " +
    "Run `npm run setup:reset-test-flow` once or set it to the Worker's DEVELOPMENT_RESET_SECRET."
  );
}

const installationID = process.env.HOTKEYGO_INSTALLATION_ID ?? readInstallationID();
if (!/^[A-Za-z0-9_-]{43}$/.test(installationID)) {
  fail("The hotkeygo installation ID is missing or invalid. Run the app once, then retry.");
}

const response = await fetch(new URL("/development/reset", endpoint), {
  method: "POST",
  headers: {
    Authorization: `Bearer ${resetSecret}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ installation_id: installationID }),
});

if (!response.ok) {
  const body = await response.text();
  fail(`Worker reset failed (${response.status}): ${body}`);
}

const result = await response.json();
if (result?.reset !== true) fail("Worker returned an invalid reset response.");

// Stop the debug app before deleting defaults so it cannot write stale values back.
try {
  execFileSync("pkill", ["-x", "HotkeyGo"], { stdio: "ignore" });
} catch {
  // The app was not running.
}

try {
  execFileSync("defaults", ["delete", "ai.hotkeygo.app"], { stdio: "ignore" });
} catch {
  // A completely fresh install has no defaults domain yet.
}

try {
  execFileSync("defaults", ["delete", "com.kiroshi.mac"], { stdio: "ignore" });
} catch {
  // The pre-rename app may never have been installed.
}

try {
  execFileSync("defaults", ["delete", "ai.qwixit.app"], { stdio: "ignore" });
} catch {
  // The previous branded build may never have been installed.
}

try {
  execFileSync(
    "security",
    ["delete-generic-password", "-s", "ai.hotkeygo.app", "-a", "installation-id"],
    { stdio: "ignore" },
  );
} catch {
  fail("The Worker was reset, but the local installation identity could not be removed from Keychain.");
}

try {
  execFileSync(
    "security",
    ["delete-generic-password", "-s", "ai.qwixit.app", "-a", "installation-id"],
    { stdio: "ignore" },
  );
} catch {
  // The previous branded build may never have created an identity.
}

try {
  execFileSync("tccutil", ["reset", "Accessibility", "ai.hotkeygo.app"], { stdio: "ignore" });
} catch {
  console.warn("Accessibility permission could not be reset automatically; remove hotkeygo in System Settings if needed.");
}

console.log("hotkeygo test flow reset.");
console.log(`Paddle sandbox subscriptions canceled: ${result.paddle_subscriptions_canceled ?? "unknown"}.`);
console.log("Run the Debug build to create a new installation and start at welcome with 30 free actions.");

function readInstallationID() {
  try {
    return execFileSync(
      "security",
      ["find-generic-password", "-s", "ai.hotkeygo.app", "-a", "installation-id", "-w"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
  } catch {
    return "";
  }
}

function readResetSecret() {
  try {
    return execFileSync(
      "security",
      ["find-generic-password", "-s", "ai.hotkeygo.development", "-a", "worker-reset-secret", "-w"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
  } catch {
    return "";
  }
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
