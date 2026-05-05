# Internal Apps Integration Guide

How Payabli-internal iOS apps integrate the Payabli SDK. External partners
should follow the public README at
[https://github.com/payabli/payabli-sdk-ios](https://github.com/payabli/payabli-sdk-ios); this doc is for teams inside
Payabli that need QA builds, bug-repro builds, or unreleased feature access.

## Quick pick


| Situation                                              | Integration mode                      |
| ------------------------------------------------------ | ------------------------------------- |
| I'm shipping the app to the App Store                  | Public repo, `from: "1.0.0"`          |
| I'm running beta against `api-sandbox.payabli.com`     | Public repo, `exact: "<latest-beta>"` |
| I'm reproducing a bug against `api-qa.payabli.com`     | Public repo, `exact: "<latest-qa>"`   |
| I need continuous integration with an in-flight branch | Private repo via SSH, `branch: …`     |
| I'm doing local SDK development                        | `.package(path: "../sdk-ios")`        |


## 1. Public-repo integration (recommended)

The public distribution repo `payabli/payabli-sdk-ios` hosts tags for all
three environments. The `Package.swift` at each tag points at the
environment-specific S3 bucket — you don't need to pick a URL by hand,
just the tag.

### Production / GA

```swift
// Package.swift
.package(
    url: "https://github.com/payabli/payabli-sdk-ios",
    from: "1.0.0"
)
```

SPM's SemVer resolver picks the latest stable `1.0.X` and never sees
`-qa` / `-beta` pre-releases. Pin with `exact:` if you need a specific
version.

### Sandbox / beta

```swift
.package(
    url: "https://github.com/payabli/payabli-sdk-ios",
    exact: "1.0.247-beta"
)
```

Check the latest beta at [https://github.com/payabli/payabli-sdk-ios/releases](https://github.com/payabli/payabli-sdk-ios/releases).
The beta `Package.swift` pulls binaries from
`payabli-public-objects-sandbox.s3.amazonaws.com`; your app talks to
`api-sandbox.payabli.com` via the usual `PayabliEnvironment.sandbox`.

### QA (bug repro)

```swift
.package(
    url: "https://github.com/payabli/payabli-sdk-ios",
    exact: "1.0.247-qa"
)
```

Use this when Support tells you "we've pushed the fix to QA, can you repro
against `1.0.247-qa`?". Binaries come from `payabli-public-objects-qa`
and should be used against `api-qa.payabli.com`.

## 2. Private-repo integration (continuous dev)

If you're tracking an in-flight feature branch inside `payabli/sdk-ios`
and don't want to wait for a QA release, you can point SPM directly at
the private repo via SSH:

```swift
.package(
    url: "git@github.com:payabli/sdk-ios.git",
    branch: "feature/new-thing"
)
```

Requirements:

- You must have an SSH key on the GitHub account linked to `payabli/sdk-ios`.
- Xcode's built-in credential helper must allow `git@github.com` (usually
works out of the box once SSH auth is set up for `git`).
- CI servers that don't have access to the private repo won't resolve this
dependency — keep this mode for local dev only, never commit it on a
shipping branch.

SPM will build the SDK from source every resolve, which is slower than
the binary distribution but lets you jump between branches instantly.

## 3. Local path integration (SDK work)

If you're actively developing the SDK itself alongside a host app:

```swift
.package(path: "../sdk-ios")
```

Assumes your app repo and the SDK repo live next to each other in the
same parent folder. SPM picks up changes to the SDK immediately on rebuild.

## Switching tiers without clearing DerivedData

SPM keeps binary artifacts under `~/Library/Caches/org.swift.swiftpm`
keyed by checksum; switching from `-qa` to `-beta` (or vice versa) triggers
a fresh download automatically. If a build gets into a weird state, reset
the SPM caches explicitly:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/<YourApp>-*
rm -rf ~/Library/Caches/org.swift.swiftpm
# From your app dir:
swift package reset
```

## Upgrading

### Host app tracking `from: "1.0.0"`

No action needed. `swift package update` on your schedule picks up the
latest stable release.

### Host app pinned with `exact:`

1. Check [https://github.com/payabli/payabli-sdk-ios/releases](https://github.com/payabli/payabli-sdk-ios/releases) for the
  tier you're on.
2. Bump your `exact:` tag; reopen Xcode (or `swift package resolve`).
3. Run the app against the matching backend environment.

## Common pitfalls

### "Checksum mismatch" error

SPM cached the old zip. Run `swift package reset && swift package resolve`
from the app directory, and restart Xcode to drop in-memory caches.

### App talks to the wrong backend

`PayabliEnvironment` controls the API host your app hits at runtime —
it's independent of the SDK tier you picked at compile time. You can
link a QA SDK build and point it at the Production API if you really want
(unsupported, but won't crash). Keep tiers aligned:


| SDK tier | Recommended `PayabliEnvironment` |
| -------- | -------------------------------- |
| `-qa`    | `.qa`                            |
| `-beta`  | `.sandbox`                       |
| GA       | `.production` (or `.sandbox`)    |


### "I need feature X today and it isn't in a tag yet"

Use the private-repo SSH path (mode 2 above). If the feature is on a PR
that hasn't merged to `develop`, you can point at the PR's head branch
directly. Don't commit this on a shipping branch.

## Support

- Integration help: `#ios-sdk` in Slack, or [sdk-support@payabli.com](mailto:sdk-support@payabli.com).
- Bug against a specific tag: include the full tag (`1.0.247-qa`) and the
relevant `PayabliEnvironment` in the report.
- SDK development: open a PR against `develop` in `payabli/sdk-ios` and
loop in the SDK maintainers.

