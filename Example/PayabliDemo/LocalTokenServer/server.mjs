import { createServer } from "node:http";

import { listTapToPayDevices, requestActivationCode } from "./lib/card-present.mjs";
import { LocalTokenServerError, publicErrorMessage, redactSensitiveText } from "./lib/errors.mjs";
import { readJsonBody, sendJson, setCorsHeaders } from "./lib/http.mjs";
import {
  bindHost,
  defaultApiBaseUrl,
  defaultEntry,
  envFilePath,
  port,
  stringValue
} from "./lib/settings.mjs";
import { exchangeCredentials, resolveAccessToken } from "./lib/tokens.mjs";

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
    // The upstream and entry point as well as liveness, so the app can report
    // "this server is on another environment" rather than leaving a token to be
    // refused later as an invalid signature. Neither is a secret: both are in
    // the startup banner already, and /payabli/devices echoes the entry.
    sendJson(res, 200, { ok: true, upstream: defaultApiBaseUrl, entry: defaultEntry || null });
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
    // The entry only. Anything else on the body would reach payabliApi as upstream options, where
    // apiBaseUrl, accessToken, clientId and clientSecret are all honoured, so a caller could spend
    // the env file's credential against any allowed host, production included.
    const { devices, unavailable } = await listTapToPayDevices(entry, {});
    sendJson(res, 200, { entry, devices, unavailable });
    return;
  }

  if (url.pathname === "/payabli/activation-code" && req.method === "POST") {
    const body = await readJsonBody(req);
    // The two fields this route documents, for the reason above.
    sendJson(res, 200, await requestActivationCode({
      entry: stringValue(body.entry),
      deviceId: stringValue(body.deviceId)
    }));
    return;
  }

  sendJson(res, 404, { error: "Not found" });
}

server.listen(port, bindHost, () => {
  console.log(`Payabli local token server listening on http://${bindHost}:${port}`);
  // The upstream and the file it came from. Without these, two runs on two environments are
  // indistinguishable in the log, and a refusal from the wrong one reads as a bad entry point.
  console.log(`Upstream:              ${defaultApiBaseUrl}`);
  console.log(`Env file:              ${envFilePath}`);
  if (defaultEntry) {
    console.log(`Entry point:           ${defaultEntry}`);
  }
  console.log(`Access token endpoint: http://${bindHost}:${port}/payabli/access-token`);
  console.log(`Tap to Pay devices:    http://${bindHost}:${port}/payabli/devices`);
  console.log(`Activation code:       http://${bindHost}:${port}/payabli/activation-code`);
  if (!defaultEntry) {
    console.log("PAYABLI_ENTRY is not set; pass entry in the request body for the Tap to Pay endpoints.");
  }
});
