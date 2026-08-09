# PayabliDemo Local Token Server

Tiny development server for PayIn payment flow QA. It gives the iOS sample a
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

Use that URL for the PayIn access-token endpoint configured in the sample app.
The capture operation aliases to the same endpoint by default.

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

## Simulator vs physical device

`127.0.0.1` resolves to a different machine in each case:

| | Simulator | Physical device |
|---|---|---|
| `127.0.0.1` is | your Mac | the phone |
| Bind the server to | `127.0.0.1` (the `.env` default) | `0.0.0.0` |
| App points at | `127.0.0.1:8787` | your Mac's LAN IP |
| Local Network permission | not required | required, granted per app |

The app resolves the host at launch, first match wins:

1. `-PayabliTokenHost <host>` launch argument (or the same `UserDefaults` key)
2. Simulator → `127.0.0.1`
3. Physical device → `Secrets.localNetworkHost`

A Simulator run needs no configuration. A device run needs the launch argument.

### Serving a physical device

```bash
PAYABLI_LOCAL_TOKEN_SERVER_HOST=0.0.0.0 node server.mjs
```

The command-line value overrides `.env`, which defaults to `127.0.0.1` and is
reachable only from the Mac. Then pass the app your Mac's LAN address:

```
-PayabliTokenHost 192.168.1.42
```

In Xcode that goes in **Product → Scheme → Edit Scheme → Run → Arguments**.

Find the address with `ifconfig | awk '/^[a-z]/ {i=$1} /inet /{print i, $2}'`. If
the Mac is on more than one network, use the address on the same network as the
phone.

Use this only on a trusted network, stop the process when finished, and prefer
short-lived sandbox credentials. Browser CORS responses are restricted to
localhost origins by default; native iOS requests do not need CORS.

Because this is plain HTTP, the app target needs an ATS local-network exception
(`NSAllowsLocalNetworking` in `Info.plist`), or an HTTPS tunnel.

### Troubleshooting

These fail as connection errors on the device while the server works on the Mac.

- **Bind `0.0.0.0`, not `::`.** On macOS, `::` binds IPv6 only and no
  IPv4-mapped listener is created. LAN connections are refused; loopback still
  works.
- **A `.local` hostname may not resolve to IPv4.** Check with
  `dns-sd -G v4 <host>.local`. If it returns `No Such Record`, the phone has
  nothing to connect to. Use the LAN IP with `-PayabliTokenHost`.
- **Local Network permission is granted per bundle identifier**, so a bundle-id
  change requires a new grant. When denied or unanswered, the request fails with
  `The Internet connection appears to be offline.` and
  `unsatisfied (Local network prohibited)` in the underlying error. Grant it at
  **Settings → Privacy & Security → Local Network**.
- **Check the server is still running.** Backgrounding it with `&` ends the
  process when the shell exits, and requests fail with
  `Could not connect to the server.`

  ```bash
  lsof -nP -iTCP:8787 -sTCP:LISTEN
  curl -s http://<mac-lan-ip>:8787/health      # {"ok":true}
  ```

## Tap to Pay Device Activation

A Tap to Pay device registers in `pending` state on first run and cannot take
payments until it is activated with a short-lived code. `initialize()` throws
`devicePendingActivation` to signal this, and the code is issued by the Payabli
API rather than generated by the SDK.

Set the entrypoint once:

```bash
PAYABLI_ENTRY=entry3715
```

List the Tap to Pay devices on it, newest first. Only `pending` devices can be
activated:

```bash
curl http://127.0.0.1:8787/payabli/devices
```

```json
{ "entry": "entry3715",
  "devices": [
    { "deviceId": "5c8a744e-...", "status": "active",  "model": "iPhone18,1", "createdAt": "..." },
    { "deviceId": "4da924ef-...", "status": "pending", "model": "iPhone18,1", "createdAt": "..." }
  ] }
```

Request the activation code:

```bash
curl -X POST http://127.0.0.1:8787/payabli/activation-code \
  -H 'Content-Type: application/json' \
  -d '{"deviceId":"4da924ef-..."}'
```

```json
{ "entry": "entry3715", "deviceId": "4da924ef-...",
  "resolvedFrom": "request",
  "code": "046192", "expiresAt": "...", "alreadyIssued": false }
```

Pass the `deviceId`. It is the only field that identifies a single device.
Serial number is the app's `identifierForVendor`, and several device records can
share one serial: one handset on this entrypoint has ten records with the same
serial, eight of them pending.

The app reads its own `deviceId` from the attestation service. Build
`PayabliTTP` with the designated initializer, keep the `AppAttestService` you
pass in, and read `cachedDeviceId` after `initialize()` reports pending
activation.

With no `deviceId`, the server uses the newest pending device. `resolvedFrom`
reports which path was used: `request`, `onlyPendingDevice`, or
`newestOfNPending`.

Device listing uses `/Cloud/list`. `/Device/list` omits pending devices.

Activation code behavior:

- 6 digits, zero-padded. Keep it a string.
- Expires in 30 minutes. 5 failed attempts discards it server-side.
- Idempotent within the validity window: an unexpired code is returned again
  with `alreadyIssued: true` rather than reissued, so a resend is a repeat call.
- A device that is already active returns
  `Activation challenge declined (400): Device is not pending activation.`

The SDK never requests an activation code. A production backend controls who
can request one and how it reaches the user.

## Contract

`GET /payabli/access-token`, `POST /payabli/access-token`, and
`POST /payabli/exchange-token` return:

```json
{ "accessToken": "..." }
```

The sample's PayIn access-token callbacks already expect this response shape.
