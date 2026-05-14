# PayabliCardReaderCore — Vendored source

This directory contains the **vendored source** of the MIT-licensed
[`Fiserv/TTPPackage`](https://github.com/Fiserv/TTPPackage), compiled into the
Payabli iOS SDK under the module name `PayabliCardReaderCore`.

## Why vendor

The Fiserv Tap-to-Phone (TTP) framework is distributed as public MIT-licensed
Swift source (not a pre-compiled binary). MIT explicitly permits modification
and redistribution under a different name, provided the original copyright
notice travels with every substantial copy of the software.

We vendor the source so that the binary XCFrameworks we ship publicly
(under `payabli/sdk-ios`) expose a **Payabli-branded module**
(`PayabliCardReaderCore`) instead of the upstream `FiservTTP` name. This
keeps the Swift Package Manager manifest, `Package.resolved`, `otool -L`
output, `CFBundleIdentifier`, and public `.swiftinterface` of the published
binary free of third-party branding, while preserving full MIT attribution
in source and in `THIRD_PARTY_LICENSES.txt` at the repository root.

## What's vendored

Byte-identical copies of the 5 Swift source files from
`Fiserv/TTPPackage/Sources/FiservTTP/`:

- `FiservPaymentModels.swift`
- `FiservTTPCardReader.swift`
- `FiservTTPModels.swift`
- `FiservTTPReader.swift`
- `FiservTTPServices.swift`

Each file keeps its original Fiserv copyright/MIT header verbatim — do not
remove or edit those headers.

## What's **not** vendored

`FiservTTP.h` (the Objective-C umbrella header). The only symbols it exports
are `FiservTTPVersionNumber` and `FiservTTPVersionString`, which are unused
by both the Fiserv source and any Payabli code. Dropping the header keeps
the vendored target purely-Swift and avoids mixed-language module-map
complications in SPM.

`FiservTTP.podspec`, `Package.swift`, `Tests/`, upstream `README.md` and
GitHub metadata — not needed for our use case.

## Upstream version pinned

| Field | Value |
|---|---|
| Repo | `github.com/Fiserv/TTPPackage` |
| Commit | `047dd91` (merge of PR #18 / COM-21492) |
| Tag | `1.0.7` |
| Vendored at | (see `git log` for `ThirdParty/PayabliCardReaderCoreSource/`) |

## Refreshing from upstream

When Fiserv publishes a newer MIT version of `TTPPackage`, re-sync with:

```bash
./Scripts/refresh_vendored_ttp.sh <upstream-tag>
```

The script:

1. `swift package resolve` to fetch the upstream checkout at the requested tag.
2. `rsync` the 5 `.swift` files into this directory (mode + time preserved).
3. Updates this README's "Upstream version pinned" block.
4. Runs `swift build` + `swift test` to verify nothing regressed.

After running, inspect the diff, commit under `chore(vendor): refresh
PayabliCardReaderCore from Fiserv/TTPPackage <tag>`, and re-cut a patch
SDK release if the upstream changes are substantive.

## Module renaming

No **in-source** renaming is performed — class names like `FiservTTPCardReader`,
`FiservTTPConfig`, etc., remain unchanged. Those types are internal
implementation detail and never appear on the Payabli SDK's public surface.
Public consumers interact with `PayabliTTP`, which wraps them.

The **module rename** is achieved entirely via the SPM target name
(`PayabliCardReaderCore`) declared in the root [`Package.swift`](../../Package.swift).
Consumers linking the binary see only `PayabliCardReaderCore` in their
`Package.resolved`, `otool -L`, and Xcode project — Fiserv's name is absent.

## MIT compliance checklist

- [x] Original Fiserv copyright header present in every `.swift` file.
- [x] Root [`THIRD_PARTY_LICENSES.txt`](../../THIRD_PARTY_LICENSES.txt) reproduces the full MIT license text
      with Fiserv as the copyright holder.
- [x] This README explicitly credits `Fiserv/TTPPackage` as the upstream.
- [x] Binary distributions ship `THIRD_PARTY_LICENSES.txt` alongside the
      XCFramework zips (see `Scripts/build_release_frameworks.sh`).
