# PayabliDemo Local Token Server

Tiny development server for payment method and payment capture QA. It gives the iOS sample a
backend-shaped endpoint without putting Payabli credentials in the app.

The server supports two local QA modes:

- Direct token mode: return a sandbox API token that can call
  `/api/TokenStorage/add` and the v2 MoneyIn auth/capture endpoints.
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

By default the server binds only to `127.0.0.1`. Keep that default when testing
in Simulator so local credentials and returned access tokens are not exposed on
your LAN.

The iOS Simulator can call:

```text
http://127.0.0.1:8787/payabli/access-token
```

Use that URL for `Secrets.partnerPaymentMethodAccessTokenEndpoint` in the sample app.
The payment capture QA screen aliases to the same endpoint by default.

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
Token exchange is restricted to Payabli hosts by default:

```bash
PAYABLI_ALLOWED_API_HOSTS=api-sandbox.payabli.com,api-qa.payabli.com,api.payabli.com
```

Only add hosts for trusted local test infrastructure. Do not point credential
exchange at arbitrary URLs, because that would send the configured
`clientSecret` to that host.

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

Upstream request details are configurable from either `.env` or the POST body,
subject to the allowed-host guard:

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

To expose the local server to a physical device, explicitly bind to all
interfaces while you are testing:

```bash
PAYABLI_LOCAL_TOKEN_SERVER_HOST=0.0.0.0 node server.mjs
```

Use this only on a trusted network, stop the process when finished, and prefer
short-lived sandbox credentials. Browser CORS responses are restricted to
localhost origins by default; native iOS requests do not need CORS.

Because this is plain HTTP for local development, the app target may need an
ATS local-network exception such as `NSAllowsLocalNetworking` in `Info.plist`,
or you can expose the server through an HTTPS tunnel.

## Contract

`GET /payabli/access-token`, `POST /payabli/access-token`, and
`POST /payabli/exchange-token` return:

```json
{ "accessToken": "..." }
```

The sample's `Secrets.fetchPaymentMethodAccessToken()` and
`Secrets.fetchPaymentCaptureAccessToken()` already expect this response shape.
