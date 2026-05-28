# PayabliDemo Local Token Server

Tiny development server for tokenization-only QA. It gives the iOS sample a
backend-shaped endpoint without putting Payabli credentials in the app.

The server supports two local QA modes:

- Direct token mode: return a sandbox API token that can call
  `/api/TokenStorage/add`.
- Credential exchange mode: post your sandbox `clientId` and `clientSecret`
  to a configurable Payabli token endpoint, then return the token from that
  response as `accessToken`.

## Setup

```bash
cd Example/PayabliDemo/LocalTokenServer
cp .env.example .env
```

Edit `.env`:

```bash
PAYABLI_ACCESS_TOKEN=<your short-lived sandbox access token>
```

Start the server:

```bash
node server.mjs
```

The iOS Simulator can call:

```text
http://127.0.0.1:8787/payabli/access-token
```

Use that URL for `Secrets.partnerTokenizationAccessTokenEndpoint` in the sample app.

## Credential Exchange Mode

If you want the local endpoint to exchange sandbox credentials, leave
`PAYABLI_ACCESS_TOKEN` blank and configure:

```bash
PAYABLI_CLIENT_ID=<your sandbox client id>
PAYABLI_CLIENT_SECRET=<your sandbox client secret>
PAYABLI_API_BASE_URL=https://api-sandbox.payabli.com/api
PAYABLI_TOKEN_PATH=/v2/token/serverside
```

That maps to Payabli's server-side token call:

```bash
curl --location 'https://api-sandbox.payabli.com/api/v2/token/serverside' \
  --header 'Content-Type: application/json' \
  --data '{
    "clientId": "{clientId}",
    "clientSecret": "{clientSecret}"
  }'
```

For QA, use:

```bash
PAYABLI_API_BASE_URL=https://api-qa.payabli.com/api
```

The server also accepts `api-sandbox.payabli.com/api` or
`api-qa.payabli.com/api` and will add `https://` automatically.

Then call the same sample URL:

```text
http://127.0.0.1:8787/payabli/access-token
```

You can also pass credentials per request for quick experiments:

```bash
curl -X POST http://127.0.0.1:8787/payabli/exchange-token \
  -H 'Content-Type: application/json' \
  -d '{
    "clientId": "sandbox-client-id",
    "clientSecret": "sandbox-client-secret"
  }'
```

Every upstream detail is overridable from either `.env` or the POST body:

```json
{
  "clientId": "...",
  "clientSecret": "...",
  "apiBaseUrl": "https://api-sandbox.payabli.com/api",
  "tokenPath": "/v2/token/serverside",
  "responseTokenField": "access_token"
}
```

If `responseTokenField` is blank, the server tries `access_token`,
`accessToken`, then `token`.

## Physical Device Notes

For a real iPhone, `127.0.0.1` points at the phone, not your Mac. Use your
Mac's LAN IP instead:

```text
http://<mac-lan-ip>:8787/payabli/access-token
```

Because this is plain HTTP for local development, the app target may need an
ATS local-network exception such as `NSAllowsLocalNetworking` in `Info.plist`,
or you can expose the server through an HTTPS tunnel.

## Contract

`GET /payabli/access-token`, `POST /payabli/access-token`, and
`POST /payabli/exchange-token` return:

```json
{ "accessToken": "..." }
```

The sample's `Secrets.fetchTokenizationAccessToken()` already expects this response shape.
