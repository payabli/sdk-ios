# PayabliDemo Local Token Server

Tiny development server standing in for a partner backend. It gives the iOS
sample somewhere to fetch a short-lived access token without putting Payabli
credentials in the app.

Every tab uses it. The card-not-present flows call it before submitting to
`/api/TokenStorage/add` and the v2 MoneyIn endpoints, and Tap to Pay calls it
through the SDK's token provider during attestation and config. It also exposes
two device endpoints for activation, documented further down.

Two modes for the token itself:

- **Direct token** — return an access token you paste into `.env`.
- **Credential exchange** — post your `clientId` and `clientSecret` to Payabli's
  token endpoint and return what comes back.

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

The app resolves the *host* itself — loopback in the Simulator, the LAN on a
device, see **Simulator vs physical device** below. What a fresh clone still has
to do is point `Secrets.swift` at this server at all: `Secrets.swift.sample`
ships a placeholder partner backend, so copy it and switch both endpoints to the
resolver:

```swift
static var partnerTokenEndpoint: URL { DemoConfiguration.TokenServer.accessTokenURL }
static var partnerPaymentMethodAccessTokenEndpoint: URL { DemoConfiguration.TokenServer.accessTokenURL }
```

Both are listed because they are separate settings; a build pointing them at
different backends is supported and honoured.

## Credential Exchange Mode

If you want the local endpoint to exchange credentials, leave
`PAYABLI_ACCESS_TOKEN` blank and configure:

```bash
PAYABLI_CLIENT_ID=<your sandbox client id>
PAYABLI_CLIENT_SECRET=<your sandbox client secret>
PAYABLI_API_BASE_URL=<the Payabli API base URL for that environment>
PAYABLI_TOKEN_PATH=/v2/token/serverside
```

Sandbox throughout, because that is what the app and `.env.example` ship. See
**Match this to the app** below before changing environment.

That maps to Payabli's server-side token call:

```bash
curl --location '<PAYABLI_API_BASE_URL>/v2/token/serverside' \
  --header 'Content-Type: application/json' \
  --data '{
    "clientId": "{clientId}",
    "clientSecret": "{clientSecret}"
  }'
```

For another environment, change this and pick the matching scheme in the app.

**Match this to the app.** A token minted for one Payabli environment is
rejected by another, and the rejection reads as a credential problem rather than
a configuration one.

The app ships `.sandbox`, which is what an integrator can reach, so
`.env.example` defaults to `api-sandbox`. Change them together. On the app side
that is the scheme: pick **PayabliDemo qa**, **PayabliDemo sandbox** or
**PayabliDemo production** in Xcode's scheme selector. Each passes
`-PayabliEnvironment`, and the entry point follows from `Secrets.entryPoints`,
so choosing a scheme cannot leave one environment's paypoint pointed at
another's host. The plain **PayabliDemo** scheme passes nothing and runs
whichever environment was chosen last.

You do not have to keep them in agreement by hand. The Config tab's health check
reads the server's own upstream and entry point from `/health` and says so when
they differ from the app's.

A bare host with a path is accepted too, and `https://` is added automatically.
Token exchange is restricted to Payabli hosts by default, and `.env.example` ships
that list along with every base URL this page leaves as a placeholder:

```bash
PAYABLI_ALLOWED_API_HOSTS=<comma-separated hosts>
```

This page covers the settings you normally touch. `.env.example` carries all
fourteen, each with a comment, and is the list to read before changing
behaviour — request-body ceiling, token cache TTL, CORS origins and the
insecure-upstream escape hatch are only there.

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
    "clientId": "your-client-id",
    "clientSecret": "your-client-secret"
  }'
```

Upstream request details are configurable from either `.env` or the POST body,
subject to the allowed-host guard:

```json
{
  "clientId": "...",
  "clientSecret": "...",
  "apiBaseUrl": "<the Payabli API base URL>",
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
short-lived credentials. Browser CORS responses are restricted to
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
  curl -s http://<mac-lan-ip>:8787/health      # upstream and entry, so a wrong environment shows here
  ```

## Tap to Pay Device Activation

A Tap to Pay device registers in `pending` state on first run and cannot take
payments until it is activated with a short-lived code. `initialize()` throws
`devicePendingActivation` to signal this, and the code is issued by the Payabli
API rather than generated by the SDK.

### Two ways to get the code

**From the dashboard.** Payabli paypoint portal → **Device Management** → find the
device → options → **Activate device**. This is the route a real operator takes,
and it is what the demo app's activation sheet points at.

**Self-service, for local QA.** The endpoints below let the same thing be
scripted end to end, which is what the rest of this section documents. A
production backend decides for itself who may request a code and how it reaches
the operator; the SDK never requests one, and neither should an app.

Set the entrypoint once:

```bash
PAYABLI_ENTRY=your-entrypoint
```

List the Tap to Pay devices on it, newest first. Only `pending` devices can be
activated:

```bash
curl http://127.0.0.1:8787/payabli/devices
```

```json
{ "entry": "your-entrypoint",
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
{ "entry": "your-entrypoint", "deviceId": "4da924ef-...",
  "resolvedFrom": "request",
  "code": "123456", "expiresAt": "...", "alreadyIssued": false }
```

Pass the `deviceId`. It is the only field that identifies a single device.
Serial number is the app's `identifierForVendor`, and several device records can
share one serial: one handset on this entrypoint has ten records with the same
serial, eight of them pending.

The app reads its own `deviceId` from the attestation service, which is reachable
from inside the SDK and from its own test targets, not from a host app.

With no `deviceId`, the server uses the newest pending device. `resolvedFrom`
reports which path was used: `request`, `onlyPendingDevice`, or
`newestOf<count>Pending` — the count is in the value, so `newestOf8Pending`
tells you the choice was made from eight candidates and is worth checking.

Device listing uses `/Cloud/list`. `/Device/list` omits pending devices.

Activation code behavior:

- 6 digits, zero-padded. Keep it a string.
- Expires in 30 minutes. 5 failed attempts discard it server-side.
- Idempotent within the validity window: an unexpired code is returned again
  with `alreadyIssued: true` rather than reissued, so a resend is a repeat call.
- A device that is already active returns
  `Activation challenge declined (400): Device is not pending activation.`

The SDK never requests an activation code. A production backend controls who
can request one and how it reaches the user.

## Contract

| Endpoint | Returns |
|---|---|
| `GET /health` | `{ "ok": true, "upstream": "<the configured upstream>", "entry": "<the configured entry point>" }`, `entry` null when none is configured |
| `GET \| POST /payabli/access-token` | `{ "accessToken": "..." }` |
| `POST /payabli/exchange-token` | `{ "accessToken": "...", "upstreamStatus": 200, "source": "credential-exchange" }` |
| `GET \| POST /payabli/devices` | `{ "entry": "...", "devices": [ … ] }` |
| `POST /payabli/activation-code` | `{ "code": "123456", "expiresAt": "...", "alreadyIssued": false, … }` |

The token shape is what the app's access-token callbacks expect. The two device
endpoints exist so device setup can be scripted; a production backend decides
for itself who may request an activation code.
