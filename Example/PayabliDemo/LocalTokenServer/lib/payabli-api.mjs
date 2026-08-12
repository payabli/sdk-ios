// One authenticated call to the Payabli API, with the allow-list applied to the endpoint it resolves.

import { LocalTokenServerError, safeJson } from "./errors.mjs";
import { defaultApiBaseUrl, stringValue } from "./settings.mjs";
import { assertAllowedEndpoint, ensureTrailingSlash, normalizeBaseUrl } from "./upstream.mjs";
import { resolveAccessToken } from "./tokens.mjs";

// Authenticated call to the Payabli API with the resolved access token.
export async function payabliApi(path, { method = "GET", body = null, options = {} } = {}) {
  const apiBaseUrl = normalizeBaseUrl(stringValue(options.apiBaseUrl) || defaultApiBaseUrl);
  const token = await resolveAccessToken(options);
  const endpoint = new URL(path.replace(/^\/+/, ""), ensureTrailingSlash(apiBaseUrl));
  assertAllowedEndpoint(endpoint, "The resolved API endpoint");

  // redirect: "manual", as the credential exchange does and for the same reason: a 307 or 308 replays
  // the method, body and Authorization header to whatever origin the Location names.
  const upstream = await fetch(endpoint, {
    method,
    redirect: "manual",
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
