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

## Cut a release

1. Open a pull request that sets the install line in `README.md` to the version being released:

   ```swift
   .package(url: "https://github.com/payabli/sdk-ios.git", .upToNextMinor(from: "0.2.0"))
   ```

   `.upToNextMinor` because a minor version can break source before 1.0.
2. Merge it, wait for **CI** on that commit to pass, then run **Release** from `main`. If publishing fails
   part way, it leaves a draft Release and no tag: delete the draft and run it again.
3. Open a pull request that moves `PayabliCore.version` to the next version.

A published number is never reused. A fix to a release is the next patch.

## A build that is not a release

Pin the commit, or build from the branch. Neither needs a tag:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", revision: "<sha>")
.package(url: "https://github.com/payabli/sdk-ios.git", branch: "<branch>")
```

Both work for an app. A package that uses version-based dependencies cannot depend on either.
