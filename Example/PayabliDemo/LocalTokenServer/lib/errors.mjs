// The error type the routes throw, and the two functions that decide what a client is told.
//
// Kept apart from everything else because every other module throws these and none of them should
// have to know how a message reaches a response.

export class LocalTokenServerError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

export function publicErrorMessage(error) {
  return redactSensitiveText(error instanceof Error ? error.message : String(error));
}

export function redactSensitiveText(value) {
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

export function safeJson(value) {
  try {
    return redactSensitiveText(JSON.stringify(value));
  } catch {
    return redactSensitiveText(String(value));
  }
}
