const API_URL = "https://qwixit-api.levmisiliuk.workers.dev/internal/analytics";
const SESSION_KEY = "tokiri.analytics.dashboard-key";
const DURATION_BUCKETS_MS = [100, 250, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 30_000, 60_000, 120_000, 300_000];
const EMPTY_HISTOGRAM = () => Array(DURATION_BUCKETS_MS.length + 1).fill(0);

const rangeSelect = document.querySelector("#rangeSelect");
const refreshButton = document.querySelector("#refreshButton");
const accessForm = document.querySelector("#accessForm");
const accessKeyInput = document.querySelector("#accessKey");
const accessMessage = document.querySelector("#accessMessage");
const accessPanel = document.querySelector("#accessPanel");
const dashboardContent = document.querySelector("#dashboardContent");
const connectionStatus = document.querySelector("#connectionStatus");
const connectionLabel = document.querySelector("#connectionLabel");

let accessKey = sessionStorage.getItem(SESSION_KEY) || "";
let requestController;

function setConnection(state, label) {
  connectionStatus.dataset.state = state;
  connectionLabel.textContent = label;
}

function setAccessMessage(message, state = "idle") {
  accessMessage.textContent = message;
  accessMessage.dataset.state = state;
}

function formatCount(value) {
  return new Intl.NumberFormat().format(value || 0);
}

function formatDuration(milliseconds) {
  if (!Number.isFinite(milliseconds)) return "—";
  if (milliseconds < 1000) return `${Math.round(milliseconds)} ms`;
  return `${(milliseconds / 1000).toFixed(1)} s`;
}

function formatPercentile(histogram, percentile = 0.95) {
  const samples = histogram.reduce((sum, count) => sum + count, 0);
  if (!samples) return "—";
  const target = Math.ceil(samples * percentile);
  let seen = 0;
  for (let index = 0; index < histogram.length; index += 1) {
    seen += histogram[index];
    if (seen >= target) {
      if (index >= DURATION_BUCKETS_MS.length) return "5+ min";
      return formatDuration(DURATION_BUCKETS_MS[index]);
    }
  }
  return "—";
}

function latencyCell(average) {
  if (!Number.isFinite(average)) {
    return '<span class="latency-cell"><strong>—</strong><small>No timing yet</small></span>';
  }
  return `<span class="latency-cell"><strong>${formatDuration(average)}</strong></span>`;
}

function providerName(provider) {
  return ({ openai: "OpenAI", anthropic: "Claude", unknown: "Other model" })[provider] || "Other model";
}

function taskName(task) {
  return ({ fix: "Fix", action: "Actions", peek: "Peek", unknown: "Other feature" })[task] || "Other feature";
}

function phaseName(phase) {
  return phase === "model" ? "The model" : "Tokiri service";
}

function stageName(stage) {
  return ({
    request_validation: "Request check",
    request_protection: "Request protection",
    worker_configuration: "Worker setup",
    usage_check: "Usage check",
    provider_request: "Provider request",
    provider_response: "Provider response",
    output_check: "Output check",
    usage_refund: "Usage refund",
    response_handling: "Response handling",
    unknown: "Stage unavailable for older event",
  })[stage] || "Stage unavailable for older event";
}

function errorDiagnosis(row) {
  const stage = stageName(row.stage || "unknown");
  if (row.outcome === "output_rejected") {
    const details = {
      max_tokens: ["Answer reached its limit", "The provider stopped after reaching its output limit."],
      provider_refusal: ["Model declined the request", "The model declined the request."],
      incomplete_response: ["Answer was cut off", "The provider returned an incomplete answer."],
      invalid_fix_json: ["Unexpected Fix format", "The Fix answer did not match the required JSON format."],
      invalid_fix_verdict: ["Unexpected Fix result", "The Fix answer used an unsupported result type."],
      invalid_action_json: ["Unexpected Actions format", "The model answer was not valid JSON with a text field."],
      malformed_response: ["Unexpected provider response", "The provider response did not match the structure Tokiri expects."],
      empty_output: ["Empty model answer", "The provider returned an empty answer."],
      selected_text_marker: ["Internal marker in answer", "The answer included an internal selection marker."],
      implausible_length: ["Unexpected answer length", "The answer was much longer or shorter than the selected text."],
    };
    const [title, detail] = details[row.reason] || ["Answer failed checks", "The answer did not pass Tokiri’s output checks."];
    return { title, detail, source: "Model output checks" };
  }
  if (row.outcome === "upstream_error") {
    return { title: "Provider request failed", source: "Model provider", detail: "The provider returned an error or the request could not reach it." };
  }
  if (row.outcome === "rate_limited") {
    return { title: "Request rate limited", source: "Tokiri request limit", detail: "Tokiri temporarily limited this request. Wait briefly, then try again." };
  }
  if (row.outcome === "quota_blocked") {
    const detail = row.reason === "free_limit_reached" ? "The 30 free actions for this month were used."
      : row.reason === "daily_limit" ? "The Advanced daily usage limit was reached."
        : row.reason === "monthly_limit" ? "The Advanced monthly usage limit was reached."
          : "The available usage limit was reached.";
    return { title: "Usage limit reached", source: "Usage limit", detail };
  }
  if (row.reason === "provider_not_configured") {
    return { title: "Provider not configured", source: "Worker setup", detail: `${providerName(row.provider)} is not configured on the Worker.` };
  }
  if (row.outcome === "client_error") {
    return { title: "Request could not be processed", source: "Request check", detail: "Check the feature and request setup." };
  }
  if (row.outcome === "worker_error") {
    return { title: "Tokiri Worker failed", source: stage, detail: `An internal error occurred during ${stage.toLowerCase()}. No model answer was accepted.` };
  }
  if (row.outcome === "service_error") {
    return { title: "Tokiri service failed", source: stage, detail: `The service could not complete this request during ${stage.toLowerCase()}.` };
  }
  return { title: "Request failed", source: stage, detail: "The source and stage show where Tokiri stopped handling the request." };
}

function rowsBy(rows, key) {
  const grouped = new Map();
  for (const row of rows) {
    const name = row[key] || "unknown";
    const total = grouped.get(name) || {
      name, count: 0, errors: 0, actionRequests: 0, failedActions: 0, modelAttempts: 0, retries: 0,
      latencyCount: 0, modelLatencyCount: 0, totalDurationMs: 0, totalModelDurationMs: 0, totalWorkerDurationMs: 0,
      maxDurationMs: 0, maxModelDurationMs: 0, maxWorkerDurationMs: 0,
      durationHistogram: EMPTY_HISTOGRAM(), modelDurationHistogram: EMPTY_HISTOGRAM(), workerDurationHistogram: EMPTY_HISTOGRAM(),
    };
    total.count += row.count;
    total.modelAttempts += row.modelAttempts;
    total.retries += row.retries || 0;
    total.totalDurationMs += row.totalDurationMs;
    total.latencyCount += row.latencyCount || 0;
    total.modelLatencyCount += row.modelLatencyCount || 0;
    total.totalModelDurationMs += row.totalModelDurationMs || 0;
    total.totalWorkerDurationMs += row.totalWorkerDurationMs || 0;
    total.maxDurationMs = Math.max(total.maxDurationMs, row.maxDurationMs || 0);
    total.maxModelDurationMs = Math.max(total.maxModelDurationMs, row.maxModelDurationMs || 0);
    total.maxWorkerDurationMs = Math.max(total.maxWorkerDurationMs, row.maxWorkerDurationMs || 0);
    for (let index = 0; index < total.durationHistogram.length; index += 1) {
      total.durationHistogram[index] += row.durationHistogram?.[index] || 0;
      total.modelDurationHistogram[index] += row.modelDurationHistogram?.[index] || 0;
      total.workerDurationHistogram[index] += row.workerDurationHistogram?.[index] || 0;
    }
    if (row.outcome !== "success") total.errors += row.count;
    if (row.task === "action") {
      total.actionRequests += row.count;
      if (row.outcome !== "success") total.failedActions += row.count;
    }
    grouped.set(name, total);
  }
  return [...grouped.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

function aggregateTotals(rows) {
  const all = rowsBy(rows, "provider");
  return all.reduce((total, row) => {
    total.requests += row.count;
    total.errors += row.errors;
    total.actionRequests += row.actionRequests;
    total.failedActions += row.failedActions;
    total.modelAttempts += row.modelAttempts;
    total.retries += row.retries;
    total.latencyCount += row.latencyCount;
    total.modelLatencyCount += row.modelLatencyCount;
    total.durationMs += row.totalDurationMs;
    total.modelDurationMs += row.totalModelDurationMs || 0;
    total.workerDurationMs += row.totalWorkerDurationMs;
    total.maxDurationMs = Math.max(total.maxDurationMs, row.maxDurationMs || 0);
    total.maxModelDurationMs = Math.max(total.maxModelDurationMs, row.maxModelDurationMs || 0);
    total.maxWorkerDurationMs = Math.max(total.maxWorkerDurationMs, row.maxWorkerDurationMs || 0);
    for (let index = 0; index < total.durationHistogram.length; index += 1) {
      total.durationHistogram[index] += row.durationHistogram[index];
      total.modelDurationHistogram[index] += row.modelDurationHistogram[index];
      total.workerDurationHistogram[index] += row.workerDurationHistogram[index];
    }
    return total;
  }, {
    requests: 0, errors: 0, actionRequests: 0, failedActions: 0, modelAttempts: 0, retries: 0, latencyCount: 0, modelLatencyCount: 0,
    durationMs: 0, modelDurationMs: 0, workerDurationMs: 0, maxDurationMs: 0, maxModelDurationMs: 0, maxWorkerDurationMs: 0,
    durationHistogram: EMPTY_HISTOGRAM(), modelDurationHistogram: EMPTY_HISTOGRAM(), workerDurationHistogram: EMPTY_HISTOGRAM(),
  });
}

function aggregateDays(rows, days) {
  const values = new Map();
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() - (days - 1));
  for (let index = 0; index < days; index += 1) {
    const date = new Date(start);
    date.setUTCDate(start.getUTCDate() + index);
    values.set(date.toISOString().slice(0, 10), { date: date.toISOString().slice(0, 10), requests: 0, failedActions: 0 });
  }
  for (const row of rows) {
    const day = values.get(row.date);
    if (!day) continue;
    day.requests += row.count;
    if (row.task === "action" && row.outcome !== "success") day.failedActions += row.count;
  }
  return [...values.values()];
}

function renderChart(rows, days) {
  const chart = document.querySelector("#trendChart");
  const data = aggregateDays(rows, days);
  const width = 900;
  const height = 230;
  const left = 42;
  const right = 10;
  const top = 12;
  const bottom = 30;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const max = Math.max(4, ...data.map((day) => day.requests));
  const step = max <= 4 ? 1 : Math.ceil(max / 4);
  const axisTop = Math.ceil(max / step) * step;
  const x = (index) => left + (data.length <= 1 ? plotWidth / 2 : (index / (data.length - 1)) * plotWidth);
  const y = (count) => top + plotHeight - (count / axisTop) * plotHeight;
  const requestPoints = data.map((day, index) => `${x(index).toFixed(1)},${y(day.requests).toFixed(1)}`).join(" ");
  const errorPoints = data.map((day, index) => `${x(index).toFixed(1)},${y(day.failedActions).toFixed(1)}`).join(" ");
  const interval = Math.max(1, Math.ceil(data.length / 6));
  const grid = Array.from({ length: 5 }, (_, index) => {
    const value = axisTop - (axisTop / 4) * index;
    const yPos = top + (plotHeight / 4) * index;
    return `<line class="chart-grid" x1="${left}" y1="${yPos}" x2="${width - right}" y2="${yPos}" />
      <text class="chart-axis-label" x="${left - 9}" y="${yPos + 3}" text-anchor="end">${formatCount(Math.round(value))}</text>`;
  }).join("");
  const dateLabels = data.map((day, index) => {
    if (index % interval !== 0 && index !== data.length - 1) return "";
    const label = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" }).format(new Date(`${day.date}T00:00:00Z`));
    const anchor = data.length === 1 ? "middle" : index === 0 ? "start" : index === data.length - 1 ? "end" : "middle";
    return `<text class="chart-axis-label" x="${x(index)}" y="${height - 7}" text-anchor="${anchor}">${label}</text>`;
  }).join("");
  const points = data.map((day, index) => `<circle class="chart-request-point" cx="${x(index)}" cy="${y(day.requests)}" r="2.7"><title>${day.date}: ${day.requests} requests</title></circle>
    ${day.failedActions ? `<circle class="chart-error-point" cx="${x(index)}" cy="${y(day.failedActions)}" r="2.7"><title>${day.date}: ${day.failedActions} Actions with errors</title></circle>` : ""}`).join("");

  chart.innerHTML = `<svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" aria-hidden="true">
    ${grid}
    <polyline class="chart-request-line" points="${requestPoints}" />
    <polyline class="chart-error-line" points="${errorPoints}" />
    ${points}${dateLabels}
  </svg>`;
  chart.setAttribute("aria-label", `${days}-day chart showing daily requests and Actions with errors. ${formatCount(aggregateTotals(rows).requests)} requests total.`);
}

function renderProviderRows(rows) {
  const grouped = rowsBy(rows, "provider");
  document.querySelector("#providerRows").innerHTML = grouped.map((row) => `<tr>
    <td><span class="provider-cell"><i class="provider-mark ${row.name}" aria-hidden="true"></i>${providerName(row.name)}</span></td>
    <td class="numeric">${formatCount(row.count)}</td>
    <td class="numeric">${countLabel(row.errors)}</td>
    <td class="numeric">${latencyCell(row.count ? row.totalDurationMs / row.count : NaN)}</td>
  </tr>`).join("") || emptyRow(4, "No requests in this period.");
}

function renderTaskRows(rows) {
  const grouped = rowsBy(rows, "task");
  document.querySelector("#taskRows").innerHTML = grouped.map((row) => `<tr>
    <td>${taskName(row.name)}</td><td class="numeric">${formatCount(row.count)}</td>
    <td class="numeric">${countLabel(row.errors)}</td>
    <td class="numeric">${latencyCell(row.count ? row.totalDurationMs / row.count : NaN)}</td>
  </tr>`).join("") || emptyRow(4, "No feature requests in this period.");
}

function countLabel(value) {
  const className = value > 0 ? "count-label count-label--error" : "count-label count-label--clear";
  return `<span class="${className}">${formatCount(value)}</span>`;
}

function renderErrorRows(rows) {
  const grouped = new Map();
  for (const row of rows) {
    if (row.outcome === "success") continue;
    const stage = row.stage || "unknown";
    const key = [row.provider, row.task, row.outcome, row.reason, stage].join("|");
    const total = grouped.get(key) || {
      ...row, stage, count: 0, latencyCount: 0, modelLatencyCount: 0, totalDurationMs: 0, totalModelDurationMs: 0,
      maxDurationMs: 0, maxModelDurationMs: 0,
      durationHistogram: EMPTY_HISTOGRAM(), modelDurationHistogram: EMPTY_HISTOGRAM(),
    };
    total.count += row.count;
    total.latencyCount += row.latencyCount || 0;
    total.modelLatencyCount += row.modelLatencyCount || 0;
    total.totalDurationMs += row.totalDurationMs;
    total.totalModelDurationMs += row.totalModelDurationMs || 0;
    total.maxDurationMs = Math.max(total.maxDurationMs, row.maxDurationMs || 0);
    total.maxModelDurationMs = Math.max(total.maxModelDurationMs, row.maxModelDurationMs || 0);
    for (let index = 0; index < total.durationHistogram.length; index += 1) {
      total.durationHistogram[index] += row.durationHistogram?.[index] || 0;
      total.modelDurationHistogram[index] += row.modelDurationHistogram?.[index] || 0;
    }
    grouped.set(key, total);
  }
  const errors = [...grouped.values()].sort((a, b) => b.count - a.count);
  document.querySelector("#errorsEmpty").hidden = errors.length > 0;
  document.querySelector("#errorRows").innerHTML = errors.map((row) => {
    const diagnosis = errorDiagnosis(row);
    return `<tr>
    <td><strong>${diagnosis.title}</strong><small class="error-explanation">${diagnosis.detail}</small><small class="mobile-context">${providerName(row.provider)} · ${taskName(row.task)}</small></td><td class="error-source">${diagnosis.source}</td><td class="error-desktop-column">${providerName(row.provider)}</td>
    <td class="error-desktop-column">${taskName(row.task)}</td><td class="numeric">${countLabel(row.count)}</td>
    <td class="numeric">${latencyCell(row.count ? row.totalDurationMs / row.count : NaN)}</td>
  </tr>`;
  }).join("");
}

function renderSlowRows(rows) {
  const sorted = [...rows].sort((a, b) => b.count - a.count || b.date.localeCompare(a.date));
  document.querySelector("#slowEmpty").hidden = sorted.length > 0;
  document.querySelector("#slowRows").innerHTML = sorted.map((row) => `<tr>
    <td>${row.date}<small class="mobile-context">${providerName(row.provider)} · ${taskName(row.task)}</small></td><td class="slow-desktop-column">${providerName(row.provider)}</td><td class="slow-desktop-column">${taskName(row.task)}</td>
    <td>${phaseName(row.phase)}</td><td class="numeric">${formatCount(row.count)}</td>
  </tr>`).join("");
}

function aggregateSlowRequests(rows) {
  return rows.reduce((total, row) => {
    total.count += row.count;
    total[row.phase] += row.count;
    return total;
  }, { count: 0, model: 0, worker: 0 });
}

function emptyRow(columnCount, text) {
  return `<tr><td colspan="${columnCount}">${text}</td></tr>`;
}

function aggregateClientTimings(rows) {
  return rows.reduce((total, row) => {
    total.count += row.count;
    total.durationMs += row.totalDurationMs;
    total.maxDurationMs = Math.max(total.maxDurationMs, row.maxDurationMs || 0);
    for (let index = 0; index < total.durationHistogram.length; index += 1) {
      total.durationHistogram[index] += row.durationHistogram?.[index] || 0;
    }
    return total;
  }, { count: 0, durationMs: 0, maxDurationMs: 0, durationHistogram: EMPTY_HISTOGRAM() });
}

function matchedTimingBreakdown(rows, clientRows) {
  const serverByDimension = new Map();
  for (const row of rows) {
    const key = [row.date, row.provider, row.task].join("|");
    const total = serverByDimension.get(key) || {
      count: 0, durationMs: 0, modelCount: 0, modelDurationMs: 0, workerDurationMs: 0,
      maxDurationMs: 0, maxModelDurationMs: 0, maxWorkerDurationMs: 0,
      durationHistogram: EMPTY_HISTOGRAM(), modelDurationHistogram: EMPTY_HISTOGRAM(), workerDurationHistogram: EMPTY_HISTOGRAM(),
    };
    const sampleCount = Number.isInteger(row.latencyCount) ? row.latencyCount : row.count;
    total.count += sampleCount;
    total.durationMs += row.totalDurationMs || 0;
    total.modelCount += row.modelLatencyCount || 0;
    total.modelDurationMs += row.totalModelDurationMs || 0;
    total.workerDurationMs += row.totalWorkerDurationMs ?? Math.max(0, (row.totalDurationMs || 0) - (row.totalModelDurationMs || 0));
    total.maxDurationMs = Math.max(total.maxDurationMs, row.maxDurationMs || 0);
    total.maxModelDurationMs = Math.max(total.maxModelDurationMs, row.maxModelDurationMs || 0);
    total.maxWorkerDurationMs = Math.max(total.maxWorkerDurationMs, row.maxWorkerDurationMs || 0);
    for (let index = 0; index < total.durationHistogram.length; index += 1) {
      total.durationHistogram[index] += row.durationHistogram?.[index] || 0;
      total.modelDurationHistogram[index] += row.modelDurationHistogram?.[index] || 0;
      total.workerDurationHistogram[index] += row.workerDurationHistogram?.[index] || 0;
    }
    serverByDimension.set(key, total);
  }

  const clientByDimension = new Map();
  for (const row of clientRows) {
    const key = [row.date, row.provider, row.task].join("|");
    const total = clientByDimension.get(key) || { count: 0, durationMs: 0 };
    total.count += row.count;
    total.durationMs += row.totalDurationMs;
    clientByDimension.set(key, total);
  }

  const matched = { count: 0, clientDurationMs: 0, serverDurationMs: 0, modelCount: 0, modelDurationMs: 0, workerDurationMs: 0,
    maxModelDurationMs: 0, maxWorkerDurationMs: 0, modelDurationHistogram: EMPTY_HISTOGRAM(), workerDurationHistogram: EMPTY_HISTOGRAM() };
  for (const [key, server] of serverByDimension) {
    const task = key.split("|")[2];
    if (task === "peek") continue;
    const client = clientByDimension.get(key);
    if (!server.count || !client || client.count !== server.count) continue;
    matched.count += server.count;
    matched.clientDurationMs += client.durationMs;
    matched.serverDurationMs += server.durationMs;
    matched.modelCount += server.modelCount;
    matched.modelDurationMs += server.modelDurationMs;
    matched.workerDurationMs += server.workerDurationMs;
    matched.maxModelDurationMs = Math.max(matched.maxModelDurationMs, server.maxModelDurationMs);
    matched.maxWorkerDurationMs = Math.max(matched.maxWorkerDurationMs, server.maxWorkerDurationMs);
    for (let index = 0; index < matched.modelDurationHistogram.length; index += 1) {
      matched.modelDurationHistogram[index] += server.modelDurationHistogram[index];
      matched.workerDurationHistogram[index] += server.workerDurationHistogram[index];
    }
  }
  return matched;
}

function renderDashboard(data) {
  const rows = Array.isArray(data.events) ? data.events : [];
  const slowRows = Array.isArray(data.slowEvents) ? data.slowEvents : [];
  const clientRows = Array.isArray(data.clientTimings) ? data.clientTimings : [];
  const total = aggregateTotals(rows);
  const client = aggregateClientTimings(clientRows);
  const matched = matchedTimingBreakdown(rows, clientRows);
  const slow = aggregateSlowRequests(slowRows);
  const days = Number(data.days) || Number(rangeSelect.value);
  document.querySelector("#totalRequests").textContent = formatCount(total.requests);
  document.querySelector("#failedActions").textContent = formatCount(total.failedActions);
  document.querySelector("#actionFailureRate").textContent = total.actionRequests
    ? `${formatCount(total.failedActions)} of ${formatCount(total.actionRequests)} Actions failed · ${formatCount(total.errors)} errors overall`
    : `No Actions yet · ${formatCount(total.errors)} errors overall`;
  const hasClientTiming = client.count > 0;
  setLatencyPair(
    "endToEndLatency",
    "endToEndP95",
    hasClientTiming ? client.durationMs / client.count : total.requests ? total.durationMs / total.requests : NaN,
    hasClientTiming ? client.durationHistogram : total.durationHistogram,
    hasClientTiming ? client.maxDurationMs : total.maxDurationMs,
  );
  if (!hasClientTiming && total.requests) {
    document.querySelector("#endToEndP95").textContent += " · Worker only until the next app build";
  }
  document.querySelector("#appWorkerLatency").textContent = matched.count
    ? formatDuration(Math.max(0, (matched.clientDurationMs - matched.serverDurationMs) / matched.count)) : "—";
  document.querySelector("#appWorkerDetail").textContent = matched.count
    ? `Estimated from ${formatCount(matched.count)} matching Fix and Actions requests` : "Available after the next app build for Fix and Actions";
  setLatencyPair("modelLatency", "modelP95", total.modelLatencyCount ? total.modelDurationMs / total.modelLatencyCount : NaN, total.modelDurationHistogram, total.modelLatencyCount ? total.maxModelDurationMs : NaN);
  setLatencyPair("workerLatency", "workerP95", total.latencyCount ? total.workerDurationMs / total.latencyCount : NaN, total.workerDurationHistogram, total.latencyCount ? total.maxWorkerDurationMs : NaN);
  document.querySelector("#slowRequests").textContent = formatCount(slow.count);
  document.querySelector("#slowBreakdown").textContent = slow.count
    ? `Model: ${formatCount(slow.model)} · Tokiri service: ${formatCount(slow.worker)}`
    : "No responses over 10 seconds";
  document.querySelector("#requestRange").textContent = `in the last ${days} days`;
  document.querySelector("#latencyCoverage").textContent = `App response timing is available for ${formatCount(client.count)} of ${formatCount(total.requests)} requests. The Fix and Actions network estimate includes both directions plus app overhead; Peek is streamed.`;
  renderChart(rows, days);
  renderProviderRows(rows);
  renderTaskRows(rows);
  renderErrorRows(rows);
  renderSlowRows(slowRows);
}

function setLatencyPair(averageID, percentileID, average, histogram, maximum) {
  document.querySelector(`#${averageID}`).textContent = formatDuration(average);
  const hasTimings = histogram.reduce((sum, count) => sum + count, 0) > 0;
  document.querySelector(`#${percentileID}`).textContent = hasTimings
    ? `95% finish in ${formatPercentile(histogram)} or less · longest ${formatDuration(maximum)}`
    : Number.isFinite(average) ? "Timing range unavailable for older requests" : "No timing data yet";
}

async function loadDashboard() {
  if (!accessKey) {
    accessPanel.hidden = false;
    dashboardContent.hidden = true;
    refreshButton.disabled = true;
    setConnection("idle", "Not connected");
    return;
  }
  requestController?.abort();
  requestController = new AbortController();
  const currentController = requestController;
  const days = rangeSelect.value;
  document.body.classList.add("is-loading");
  refreshButton.disabled = true;
  refreshButton.textContent = "Loading…";
  setConnection("idle", "Loading activity");
  setAccessMessage("");
  try {
    const response = await fetch(`${API_URL}?days=${encodeURIComponent(days)}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${accessKey}` },
      cache: "no-store",
      signal: currentController.signal,
    });
    if (response.status === 401) throw new Error("That key did not work. Check it and try again.");
    if (response.status === 404) throw new Error("Activity data is not available yet.");
    if (response.status === 403) throw new Error("This page is not allowed to open the dashboard.");
    if (!response.ok) throw new Error("Could not load activity. Try again shortly.");
    const data = await response.json();
    renderDashboard(data);
    accessPanel.hidden = true;
    dashboardContent.hidden = false;
    refreshButton.disabled = false;
    setConnection("connected", "Dashboard connected");
  } catch (error) {
    if (error.name === "AbortError") return;
    const message = error instanceof TypeError
      ? "Could not reach the service. Check your connection and try again."
      : error.message || "Could not load activity.";
    setConnection("error", "Connection error");
    accessPanel.hidden = false;
    dashboardContent.hidden = true;
    refreshButton.disabled = true;
    setAccessMessage(message, "error");
  } finally {
    if (requestController === currentController) {
      document.body.classList.remove("is-loading");
      refreshButton.textContent = "Refresh";
      refreshButton.disabled = !accessKey || dashboardContent.hidden;
    }
  }
}

accessForm.addEventListener("submit", (event) => {
  event.preventDefault();
  accessKey = accessKeyInput.value.trim();
  if (!accessKey) return;
  sessionStorage.setItem(SESSION_KEY, accessKey);
  loadDashboard();
});

rangeSelect.addEventListener("change", loadDashboard);
refreshButton.addEventListener("click", loadDashboard);
document.querySelector("#disconnectButton").addEventListener("click", () => {
  requestController?.abort();
  accessKey = "";
  sessionStorage.removeItem(SESSION_KEY);
  accessKeyInput.value = "";
  setAccessMessage("Dashboard key cleared from this tab.");
  loadDashboard();
});

if (accessKey) loadDashboard();
