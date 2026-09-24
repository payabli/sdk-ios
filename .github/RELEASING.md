# Releasing

A consumer resolves this package by git tag, so a tag is a release, and only a release is ever tagged.
**Release** (`release.yml`) creates one, and nothing else does. It refuses to start until **CI** has
completed with success on the commit it runs from, then derives the version from the tree, runs the test
suite, builds the XCFrameworks, and creates the tag and the GitHub Release on the commit it tested.

The GitHub Release carries the XCFramework zips, `checksums.txt` and `THIRD_PARTY_LICENSES.txt`. SwiftPM
resolves the tag's source; the zips are for integrators who do not use SwiftPM.

The version is `PayabliCore.version` in `Sources/PayabliSDKCore/PayabliSDKCore.swift`: the version the tree
is heading for, which every module reports. There is no `v` prefix, because SwiftPM reads the tag name as the
version itself.

## Who may release

The `release` environment decides it. The job runs in that environment, so it waits for one of its required
reviewers, deploys from `main` only, and is the only job that can read `RELEASE_DEPLOY_KEY`. That deploy key is
the only identity the tag ruleset lets create a tag, so nothing else can publish a version.

Set up once, by a repository admin:

```bash
ssh-keygen -t ed25519 -N "" -C "sdk-ios release" -f release_key
gh repo deploy-key add release_key.pub --repo payabli/sdk-ios --allow-write --title "release"
gh secret set RELEASE_DEPLOY_KEY --repo payabli/sdk-ios --env release < release_key
rm release_key release_key.pub
```

Then add **Deploy keys** to the tag ruleset's bypass list. That bypass covers every deploy key with write
access, so this is the only one there may be.

## Cut a release

1. Open a pull request that sets the install line in `README.md` to the version being released:

   ```swift
   .package(url: "https://github.com/payabli/sdk-ios.git", .upToNextMinor(from: "0.2.0"))
   ```

   `.upToNextMinor` because a minor version can break source before 1.0.
2. Merge it, wait for **CI** on that commit to pass, then run **Release** from `main` and approve it. If
   publishing fails before the tag is pushed, it leaves a draft Release: delete the draft and run it again.
   If it fails after, the tag exists and `gh release edit <version> --draft=false` publishes its draft.
3. Open a pull request that moves `PayabliCore.version` to the next version.

A published number is never reused. A fix to a release is the next patch.

## A build that is not a release

Pin the commit, or build from the branch. Neither needs a tag:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", revision: "<sha>")
.package(url: "https://github.com/payabli/sdk-ios.git", branch: "<branch>")
```

Both work for an app. A package that uses version-based dependencies cannot depend on either.
