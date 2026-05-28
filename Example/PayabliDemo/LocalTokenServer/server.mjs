import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = dirname(fileURLToPath(import.meta.url));
loadEnv(join(serverDir, ".env"));

const port = Number.parseInt(process.env.PORT || "8787", 10);
const bindHost = stringValue(process.env.PAYABLI_LOCAL_TOKEN_SERVER_HOST) || "127.0.0.1";
const defaultApiBaseUrl = process.env.PAYABLI_API_BASE_URL || "https://api-sandbox.payabli.com/api";
const defaultTokenPath = process.env.PAYABLI_TOKEN_PATH || "/v2/token/serverside";
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

  sendJson(res, 404, { error: "Not found" });
}

server.listen(port, bindHost, () => {
  console.log(`Payabli local token server listening on http://${bindHost}:${port}`);
  console.log(`Access token endpoint: http://${bindHost}:${port}/payabli/access-token`);
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
    .replace(
      /((?:access_token|accessToken|token|clientSecret|client_secret|secret)=)[^\s&]+/gi,
      "$1[REDACTED]"
    );
}
