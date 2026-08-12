// Loads the env file, and exports the settings shared across the server.
//
// Loading happens here rather than in server.mjs so that importing any module below reads the same
// values whatever the import order.
//
// Not every read of process.env lives here. tokens.mjs reads the access token and the client
// credentials where it uses them, because a request can override each of them and exporting them
// would put the secret in a module every other one imports.

import { existsSync, readFileSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = dirname(join(fileURLToPath(import.meta.url), ".."));

// PAYABLI_ENV_FILE picks the file, so a second environment is a second file rather than an edit to
// this one. A relative name resolves beside this server. An explicitly named file that is not there
// is fatal: the alternative is falling back to the sandbox defaults below and reporting nothing.
const envFileName = (process.env.PAYABLI_ENV_FILE || ".env").trim();

const envFilePath = isAbsolute(envFileName) ? envFileName : join(serverDir, envFileName);
if (process.env.PAYABLI_ENV_FILE && !existsSync(envFilePath)) {
  console.error(`PAYABLI_ENV_FILE=${envFileName} does not exist at ${envFilePath}`);
  process.exit(1);
}
loadEnv(envFilePath);

loadEnv(envFilePath);

export { envFilePath };

export const port = Number.parseInt(process.env.PORT || "8787", 10);

export const bindHost = stringValue(process.env.PAYABLI_LOCAL_TOKEN_SERVER_HOST) || "127.0.0.1";
// Sandbox, matching what the app and .env.example ship. Override with PAYABLI_API_BASE_URL.

// Sandbox, matching what the app and .env.example ship. Override with PAYABLI_API_BASE_URL.
export const defaultApiBaseUrl = process.env.PAYABLI_API_BASE_URL || "https://api-sandbox.payabli.com/api";

export const defaultTokenPath = process.env.PAYABLI_TOKEN_PATH || "/v2/token/serverside";

export const defaultEntry = (process.env.PAYABLI_ENTRY || "").trim();

export const responseTokenField = (process.env.PAYABLI_RESPONSE_TOKEN_FIELD || "").trim();

export const cacheTtlSeconds = Number.parseInt(process.env.PAYABLI_TOKEN_CACHE_TTL_SECONDS || "300", 10);

export const maxRequestBodyBytes = Number.parseInt(process.env.PAYABLI_MAX_REQUEST_BODY_BYTES || "32768", 10);

export const allowedApiHosts = parseCsvSet(
  process.env.PAYABLI_ALLOWED_API_HOSTS ||
    "api-sandbox.payabli.com,api-qa.payabli.com,api.payabli.com"
);
export const allowInsecureUpstream = process.env.PAYABLI_ALLOW_INSECURE_UPSTREAM === "true";

export const configuredCorsOrigins = parseCsvSet(process.env.PAYABLI_ALLOWED_CORS_ORIGINS || "");

export function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

export function parseCsvSet(value) {
  return new Set(
    value
      .split(",")
      .map((item) => item.trim().toLowerCase())
      .filter(Boolean)
  );
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
