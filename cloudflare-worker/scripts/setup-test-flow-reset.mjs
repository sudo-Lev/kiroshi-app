import { execFileSync, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";

const secret = randomBytes(32).toString("base64url");
const wrangler = spawnSync(
  "npx",
  ["wrangler", "secret", "put", "DEVELOPMENT_RESET_SECRET"],
  { input: `${secret}\n`, stdio: ["pipe", "inherit", "inherit"] },
);

if (wrangler.error) fail(`Could not run Wrangler: ${wrangler.error.message}`);
if (wrangler.status !== 0) fail(`Wrangler exited with status ${wrangler.status}.`);

try {
  execFileSync(
    "security",
    [
      "add-generic-password",
      "-U",
      "-s", "ai.qwixit.development",
      "-a", "worker-reset-secret",
      "-w", secret,
    ],
    { stdio: "ignore" },
  );
} catch {
  fail("The Worker secret was created, but it could not be saved in macOS Keychain.");
}

console.log("Development reset secret configured in Cloudflare and saved in macOS Keychain.");
console.log("Now add a sandbox Paddle API key with Subscription Read and Write permissions:");

const paddleSecret = spawnSync(
  "npx",
  ["wrangler", "secret", "put", "PADDLE_API_KEY"],
  { stdio: "inherit" },
);
if (paddleSecret.error) fail(`Could not run Wrangler: ${paddleSecret.error.message}`);
if (paddleSecret.status !== 0) fail(`Wrangler exited with status ${paddleSecret.status}.`);

console.log("Complete test-flow reset configured.");
console.log("Run `npm run deploy` once, then use `npm run reset:test-flow` whenever needed.");

function fail(message) {
  console.error(message);
  process.exit(1);
}
