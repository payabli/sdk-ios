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

Modified copies of the 5 Swift source files from
`Fiserv/TTPPackage/Sources/FiservTTP/`:

- `FiservPaymentModels.swift`
- `FiservTTPCardReader.swift`
- `FiservTTPModels.swift`
- `FiservTTPReader.swift`
- `FiservTTPServices.swift`

Each file keeps its original Fiserv copyright/MIT header verbatim — do not
remove or edit those headers.

These files carry implementation improvements. See `git log` for this directory.

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

**A refresh is a merge, never an overwrite.** These copies carry changes of our
own, so replacing a file with the upstream version silently drops them. Resolve
the upstream checkout at the new tag, diff each of the 5 files against it, and
take the upstream changes into ours rather than the other way round. Upstream
declarations arrive `public`; each one merged in becomes `package`.

`Scripts/refresh_vendored_ttp.sh`, which earlier versions of this file
described, does not exist. It was specified as an `rsync` of the 5 files, which
is the overwrite the paragraph above rules out. Whoever writes it makes it apply
the upstream diff instead, and until then the merge is done by hand.

Either way: read the diff before committing, commit under `chore(vendor):
refresh PayabliCardReaderCore from Fiserv/TTPPackage <tag>`, update the
"Upstream version pinned" block, run the test suite on a simulator destination,
and re-cut a patch SDK release if the upstream changes are substantive.

## Module renaming

No **in-source** renaming is performed — class names like `FiservTTPCardReader`,
`FiservTTPConfig`, etc., remain unchanged. Every declaration upstream marks
`public` is `package` here, so `PayabliSDKTapToPay` reaches them and a host app
does not. Public consumers interact with `PayabliTTP`, which wraps them.

The **module rename** is achieved entirely via the SPM target name
(`PayabliCardReaderCore`) declared in the root [`Package.swift`](../../Package.swift).
The module is not a product. It is linked statically into `PayabliSDKTapToPay`,
which loads no separate reader framework, so Fiserv's name is absent from a
consumer's `otool -L`.

## MIT compliance checklist

- [x] Original Fiserv copyright header present in every `.swift` file.
- [x] Root [`THIRD_PARTY_LICENSES.txt`](../../THIRD_PARTY_LICENSES.txt) reproduces the full MIT license text
      with Fiserv as the copyright holder.
- [x] This README explicitly credits `Fiserv/TTPPackage` as the upstream.
- [x] A release tag carries `THIRD_PARTY_LICENSES.txt` at the repository root,
      and `Scripts/build_release_frameworks.sh` copies it beside the XCFramework
      zips it builds.
