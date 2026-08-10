import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = dirname(fileURLToPath(import.meta.url));
loadEnv(join(serverDir, ".env"));

const port = Number.parseInt(process.env.PORT || "8787", 10);
const bindHost = stringValue(process.env.PAYABLI_LOCAL_TOKEN_SERVER_HOST) || "127.0.0.1";
// QA, matching what the app and .env.example ship. Override with PAYABLI_API_BASE_URL.
const defaultApiBaseUrl = process.env.PAYABLI_API_BASE_URL || "https://api-qa.payabli.com/api";
const defaultTokenPath = process.env.PAYABLI_TOKEN_PATH || "/v2/token/serverside";
const defaultEntry = (process.env.PAYABLI_ENTRY || "").trim();
const responseTokenField = (process.env.PAYABLI_RESPONSE_TOKEN_FIELD || "").trim();
const cacheTtlSeconds = Number.parseInt(process.env.PAYABLI_TOKEN_CACHE_TTL_SECONDS || "300", 10);
const maxRequestBodyBytes = Number.parseInt(process.env.PAYABLI_MAX_REQUEST_BODY_BYTES || "32768", 10);
const allowedApiHosts = parseCsvSet(
  process.env.PAYABLI_ALLOWED_API_HOSTS ||
    "api-sandbox.payabli.com,api-qa.payabli.com,api.payabli.com"
);
const configuredCorsOrigins = parseCsvSet(process.env.PAYABLI_ALLOWED_CORS_ORIGINS || "");
const tokenCache = new Map();

class LocalTokenServerError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

const server = createServer((req, res) => {
  handleRequest(req, res).catch((error) => {
    console.error(redactSensitiveText(error instanceof Error ? error.stack || error.message : String(error)));
    const statusCode = error instanceof LocalTokenServerError ? error.statusCode : 500;
    sendJson(res, statusCode, {
      error: "Local token server failed",
      detail: publicErrorMessage(error)
    });
  });
});

async function handleRequest(req, res) {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  const corsAllowed = setCorsHeaders(req, res);

  if (req.method === "OPTIONS") {
    res.writeHead(corsAllowed ? 204 : 403);
    res.end();
    return;
  }

  if (!corsAllowed) {
    sendJson(res, 403, { error: "Origin not allowed" });
    return;
  }

  if (url.pathname === "/health" && req.method === "GET") {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (url.pathname === "/payabli/access-token" && ["GET", "POST"].includes(req.method || "")) {
    const body = req.method === "POST" ? await readJsonBody(req) : {};
    const token = await resolveAccessToken(body);
    sendJson(res, 200, { accessToken: token });
    return;
  }

  if (url.pathname === "/payabli/exchange-token" && req.method === "POST") {
    const body = await readJsonBody(req);
    const exchange = await exchangeCredentials(body, { forceRefresh: true });
    sendJson(res, 200, {
      accessToken: exchange.token,
      upstreamStatus: exchange.upstreamStatus,
      source: "credential-exchange"
    });
    return;
  }

  if (url.pathname === "/payabli/devices" && ["GET", "POST"].includes(req.method || "")) {
    const body = req.method === "POST" ? await readJsonBody(req) : {};
    const entry = stringValue(body.entry) || stringValue(url.searchParams.get("entry")) || defaultEntry;
    const devices = await listTapToPayDevices(entry, body);
    sendJson(res, 200, { entry, devices });
    return;
  }

  if (url.pathname === "/payabli/activation-code" && req.method === "POST") {
    const body = await readJsonBody(req);
    sendJson(res, 200, await requestActivationCode(body));
    return;
  }

  sendJson(res, 404, { error: "Not found" });
}

server.listen(port, bindHost, () => {
  console.log(`Payabli local token server listening on http://${bindHost}:${port}`);
  console.log(`Access token endpoint: http://${bindHost}:${port}/payabli/access-token`);
  console.log(`Tap to Pay devices:    http://${bindHost}:${port}/payabli/devices`);
  console.log(`Activation code:       http://${bindHost}:${port}/payabli/activation-code`);
  if (!defaultEntry) {
    console.log("PAYABLI_ENTRY is not set; pass entry in the request body for the Tap to Pay endpoints.");
  }
});

async function resolveAccessToken(options = {}) {
  const directToken = stringValue(options.accessToken) || stringValue(process.env.PAYABLI_ACCESS_TOKEN);
  if (directToken) {
    return directToken;
  }

  const exchange = await exchangeCredentials(options);
  return exchange.token;
}

async function exchangeCredentials(options = {}, { forceRefresh = false } = {}) {
  const clientId = stringValue(options.clientId) || stringValue(process.env.PAYABLI_CLIENT_ID);
  const clientSecret = stringValue(options.clientSecret) || stringValue(process.env.PAYABLI_CLIENT_SECRET);
  const apiBaseUrl = normalizeBaseUrl(stringValue(options.apiBaseUrl) || defaultApiBaseUrl);
  const tokenPath = normalizeTokenPath(stringValue(options.tokenPath) || defaultTokenPath);
  const tokenField = stringValue(options.responseTokenField) || responseTokenField;

  if (!clientId || !clientSecret) {
    throw new Error(
      "Set PAYABLI_ACCESS_TOKEN, or provide PAYABLI_CLIENT_ID and PAYABLI_CLIENT_SECRET for credential exchange."
    );
  }

  const cacheKey = JSON.stringify({
    clientIdHash: sha256(clientId),
    clientSecretHash: sha256(clientSecret),
    apiBaseUrl,
    tokenPath,
    tokenField
  });
  const cached = tokenCache.get(cacheKey);
  if (!forceRefresh && cached && cached.expiresAt > Date.now()) {
    return { token: cached.token, upstreamStatus: 200 };
  }

  const endpoint = new URL(tokenPath.replace(/^\/+/, ""), ensureTrailingSlash(apiBaseUrl));
  const upstream = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ clientId, clientSecret })
  });

  const text = await upstream.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    payload = { raw: text };
  }

  if (!upstream.ok) {
    throw new Error(
      `Payabli token exchange failed with HTTP ${upstream.status}: ${safeJson(payload)}`
    );
  }

  const token = extractToken(payload, tokenField);
  if (!token) {
    throw new Error(
      `Payabli token exchange response did not include a token field. Response keys: ${Object.keys(payload).join(", ")}`
    );
  }

  if (cacheTtlSeconds > 0) {
    tokenCache.set(cacheKey, {
      token,
      expiresAt: Date.now() + cacheTtlSeconds * 1000
    });
  }

  return { token, upstreamStatus: upstream.status };
}

// Authenticated call to the Payabli API with the resolved access token.
async function payabliApi(path, { method = "GET", body = null, options = {} } = {}) {
  const apiBaseUrl = normalizeBaseUrl(stringValue(options.apiBaseUrl) || defaultApiBaseUrl);
  const token = await resolveAccessToken(options);
  const endpoint = new URL(path.replace(/^\/+/, ""), ensureTrailingSlash(apiBaseUrl));

  const upstream = await fetch(endpoint, {
    method,
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`
    },
    body: body === null ? undefined : JSON.stringify(body)
  });

  const text = await upstream.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    payload = { raw: text };
  }

  if (!upstream.ok) {
    throw new LocalTokenServerError(
      upstream.status >= 500 ? 502 : upstream.status,
      `Payabli ${path} failed with HTTP ${upstream.status}: ${safeJson(payload)}`
    );
  }

  return payload;
}

// These endpoints report failure as HTTP 200 with `isSuccess: false`, so the
// real outcome is in the envelope rather than the transport status.
function envelopeDecline(payload) {
  if (!payload || payload.isSuccess !== false) {
    return null;
  }

  const data = payload.responseData || {};
  return {
    code: Number(data.resultCode) || 0,
    text: stringValue(data.resultText) || stringValue(payload.responseText) || "Declined"
  };
}

// Observed values. Anything else is passed through as its raw number rather
// than guessed at.
const DEVICE_STATUS_ACTIVE = 1;
const DEVICE_STATUS_PENDING = 2;

function deviceStatusLabel(status) {
  if (status === DEVICE_STATUS_ACTIVE) return "active";
  if (status === DEVICE_STATUS_PENDING) return "pending";
  return `status-${status}`;
}

async function describeDevice(entry, deviceId, options = {}) {
  const payload = await payabliApi(
    `/Device/get/${encodeURIComponent(entry)}/${encodeURIComponent(deviceId)}`,
    { options }
  );
  return envelopeDecline(payload) ? null : payload.responseData || null;
}

// `/Device/list` omits pending devices, which are the only ones that can be
// activated, so the fuller `/Cloud/list` is the source and each row is then
// described individually to get its status.
async function listTapToPayDevices(entry, options = {}) {
  if (!entry) {
    throw new LocalTokenServerError(400, "Set PAYABLI_ENTRY in .env, or pass entry in the request.");
  }

  const payload = await payabliApi(`/Cloud/list/${encodeURIComponent(entry)}`, { options });
  const decline = envelopeDecline(payload);
  if (decline) {
    throw new LocalTokenServerError(400, `Device list declined (${decline.code}): ${decline.text}`);
  }

  const rows = Array.isArray(payload.responseList) ? payload.responseList : [];
  const described = [];
  for (let index = 0; index < rows.length; index += 6) {
    const batch = await Promise.all(
      rows.slice(index, index + 6).map((row) => describeDevice(entry, row.deviceId, options))
    );
    described.push(...batch);
  }

  return described
    .filter((device) => device && stringValue(device.deviceType).toLowerCase() === "softpos")
    .map((device) => ({
      deviceId: device.deviceId,
      status: deviceStatusLabel(device.deviceStatus),
      deviceStatus: device.deviceStatus,
      model: device.model,
      serialNumber: device.serialNumber,
      friendlyName: device.friendlyName,
      createdAt: device.createdAt,
      updatedAt: device.updatedAt
    }))
    .sort((a, b) => String(b.createdAt || "").localeCompare(String(a.createdAt || "")));
}

// Requests the activation code for a pending device. Idempotent upstream: an
// unexpired code is returned again rather than reissued.
async function requestActivationCode(options = {}) {
  const entry = stringValue(options.entry) || defaultEntry;
  if (!entry) {
    throw new LocalTokenServerError(400, "Set PAYABLI_ENTRY in .env, or pass entry in the request.");
  }

  let deviceId = stringValue(options.deviceId);
  let resolvedFrom = "request";

  // A serial number is the app's identifierForVendor and is shared by every
  // record a reinstall leaves behind, so it cannot pick one device out. Only a
  // deviceId does. Falling back to the newest pending device is a convenience
  // for a single-device QA setup, and reports itself as such.
  if (!deviceId) {
    const devices = await listTapToPayDevices(entry, options);
    const pending = devices.filter((device) => device.deviceStatus === DEVICE_STATUS_PENDING);

    if (pending.length === 0) {
      throw new LocalTokenServerError(
        404,
        `No pending Tap to Pay devices on ${entry}. Pass deviceId to target a specific device.`
      );
    }

    deviceId = stringValue(pending[0].deviceId);
    resolvedFrom = pending.length === 1 ? "onlyPendingDevice" : `newestOf${pending.length}Pending`;
  }

  const payload = await payabliApi("/v2/device/taptopay/activate/challenge", {
    method: "POST",
    body: { entry, deviceId },
    options
  });

  const decline = envelopeDecline(payload);
  if (decline) {
    throw new LocalTokenServerError(
      decline.code === 404 ? 404 : 400,
      `Activation challenge declined (${decline.code}): ${decline.text}`
    );
  }

  const data = payload.responseData || {};
  return {
    entry,
    deviceId,
    resolvedFrom,
    code: stringValue(data.code),
    expiresAt: stringValue(data.expiresAt),
    alreadyIssued: Boolean(data.alreadyIssued)
  };
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff"
  });
  res.end(JSON.stringify(body));
}

function setCorsHeaders(req, res) {
  const origin = req.headers.origin;
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
  if (!origin) {
    return true;
  }
  if (!isAllowedCorsOrigin(origin)) {
    return false;
  }
  res.setHeader("Access-Control-Allow-Origin", origin);
  return true;
}

function loadEnv(path) {
  if (!existsSync(path)) {
    return;
  }

  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }

    const separatorIndex = line.indexOf("=");
    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = stripQuotes(line.slice(separatorIndex + 1).trim());
    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function stripQuotes(value) {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }

  return value;
}

function extractToken(payload, configuredField) {
  if (configuredField) {
    return stringValue(valueAtPath(payload, configuredField));
  }

  for (const field of ["access_token", "accessToken", "token"]) {
    const token = stringValue(valueAtPath(payload, field));
    if (token) {
      return token;
    }
  }

  return "";
}

function valueAtPath(value, path) {
  return path.split(".").reduce((current, key) => {
    if (current && typeof current === "object" && key in current) {
      return current[key];
    }
    return undefined;
  }, value);
}

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function ensureTrailingSlash(url) {
  return url.endsWith("/") ? url : `${url}/`;
}

function normalizeBaseUrl(url) {
  const trimmed = url.trim();
  const normalized = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  const parsed = new URL(normalized);

  if (parsed.protocol !== "https:" && process.env.PAYABLI_ALLOW_INSECURE_UPSTREAM !== "true") {
    throw new LocalTokenServerError(400, "PAYABLI_API_BASE_URL must use https.");
  }

  if (!allowedApiHosts.has(parsed.hostname.toLowerCase())) {
    throw new LocalTokenServerError(
      400,
      `PAYABLI_API_BASE_URL host is not allowed. Allowed hosts: ${Array.from(allowedApiHosts).join(", ")}`
    );
  }

  return parsed.toString();
}

function normalizeTokenPath(path) {
  const trimmed = path.trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed)) {
    throw new LocalTokenServerError(400, "PAYABLI_TOKEN_PATH must be a path, not an absolute URL.");
  }
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
}

function safeJson(value) {
  try {
    return redactSensitiveText(JSON.stringify(value));
  } catch {
    return redactSensitiveText(String(value));
  }
}

async function readJsonBody(req) {
  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (totalBytes > maxRequestBodyBytes) {
      throw new LocalTokenServerError(413, `Request body is too large. Maximum is ${maxRequestBodyBytes} bytes.`);
    }
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) {
    return {};
  }

  try {
    return JSON.parse(raw);
  } catch {
    throw new LocalTokenServerError(400, "Request body must be valid JSON.");
  }
}

function parseCsvSet(value) {
  return new Set(
    value
      .split(",")
      .map((item) => item.trim().toLowerCase())
      .filter(Boolean)
  );
}

function isAllowedCorsOrigin(origin) {
  if (configuredCorsOrigins.has(origin.toLowerCase())) {
    return true;
  }

  if (configuredCorsOrigins.size > 0) {
    return false;
  }

  try {
    const parsed = new URL(origin);
    return ["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsed.hostname.toLowerCase());
  } catch {
    return false;
  }
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function publicErrorMessage(error) {
  return redactSensitiveText(error instanceof Error ? error.message : String(error));
}

function redactSensitiveText(value) {
  return value
    .replace(/(bearer\s+)[a-z0-9._~+/-]+=*/gi, "$1[REDACTED]")
    .replace(
      /("(?:access_token|accessToken|token|clientSecret|client_secret|secret)"\s*:\s*)"[^"]*"/gi,
      '$1"[REDACTED]"'
    )
    .replace(/("(?:code|activationCode)"\s*:\s*)"[^"]*"/gi, '$1"[REDACTED]"')
    .replace(
      /((?:access_token|accessToken|token|clientSecret|client_secret|secret)=)[^\s&]+/gi,
      "$1[REDACTED]"
    );
}
