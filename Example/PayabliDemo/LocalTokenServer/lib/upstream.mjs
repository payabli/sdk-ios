// Where a request is allowed to go, and nothing else.
//
// assertAllowedEndpoint is applied to the configured base and to every endpoint resolved from it: a
// path can steer resolution onto another origin, so checking the base alone leaves the credential
// reachable.

import { LocalTokenServerError } from "./errors.mjs";
import { allowInsecureUpstream, allowedApiHosts } from "./settings.mjs";

export function ensureTrailingSlash(url) {
  return url.endsWith("/") ? url : `${url}/`;
}

export function normalizeBaseUrl(url) {
  const trimmed = url.trim();
  const normalized = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  const parsed = new URL(normalized);
  assertAllowedEndpoint(parsed, "PAYABLI_API_BASE_URL");
  return parsed.toString();
}

// Checks a URL that is about to receive the credentials. Applied to the configured base and, more
// importantly, to the endpoint actually resolved from base + path: a path can steer that resolution
// onto another origin, so validating the base alone leaves the credential reachable.
export function assertAllowedEndpoint(parsed, label) {
  if (parsed.protocol !== "https:" && !allowInsecureUpstream) {
    throw new LocalTokenServerError(400, `${label} must use https.`);
  }

  if (!allowedApiHosts.has(parsed.hostname.toLowerCase())) {
    throw new LocalTokenServerError(
      400,
      `${label} host is not allowed. Allowed hosts: ${Array.from(allowedApiHosts).join(", ")}`
    );
  }

  return parsed.toString();
}

export function normalizeTokenPath(path) {
  const trimmed = path.trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed)) {
    throw new LocalTokenServerError(400, "PAYABLI_TOKEN_PATH must be a path, not an absolute URL.");
  }
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
}
