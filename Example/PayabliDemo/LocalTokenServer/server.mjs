import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = dirname(fileURLToPath(import.meta.url));
loadEnv(join(serverDir, ".env"));

const port = Number.parseInt(process.env.PORT || "8787", 10);
const defaultApiBaseUrl = process.env.PAYABLI_API_BASE_URL || "https://api-sandbox.payabli.com/api";
const defaultTokenPath = process.env.PAYABLI_TOKEN_PATH || "/v2/token/serverside";
const responseTokenField = (process.env.PAYABLI_RESPONSE_TOKEN_FIELD || "").trim();
const cacheTtlSeconds = Number.parseInt(process.env.PAYABLI_TOKEN_CACHE_TTL_SECONDS || "300", 10);
const tokenCache = new Map();

const server = createServer((req, res) => {
  handleRequest(req, res).catch((error) => {
    console.error(error);
    sendJson(res, 500, {
      error: "Local token server failed",
      detail: error instanceof Error ? error.message : String(error)
    });
  });
});

async function handleRequest(req, res) {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

  setCorsHeaders(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
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

server.listen(port, "0.0.0.0", () => {
  console.log(`Payabli local token server listening on http://127.0.0.1:${port}`);
  console.log(`Access token endpoint: http://127.0.0.1:${port}/payabli/access-token`);
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
  const tokenPath = stringValue(options.tokenPath) || defaultTokenPath;
  const tokenField = stringValue(options.responseTokenField) || responseTokenField;

  if (!clientId || !clientSecret) {
    throw new Error(
      "Set PAYABLI_ACCESS_TOKEN, or provide PAYABLI_CLIENT_ID and PAYABLI_CLIENT_SECRET for credential exchange."
    );
  }

  const cacheKey = JSON.stringify({ clientId, clientSecret, apiBaseUrl, tokenPath, tokenField });
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
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

function setCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
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
  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed;
  }

  return `https://${trimmed}`;
}

function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) {
    return {};
  }

  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("Request body must be valid JSON.");
  }
}
