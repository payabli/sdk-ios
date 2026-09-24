# Releasing

A consumer resolves this package by git tag, so a tag is a release. Two workflows create one, and nothing
else does. Each derives the version from the tree, runs the test suite, and tags the commit it tested.

| Workflow | Tag | Run from | GitHub Release |
|---|---|---|---|
| **Release** (`release.yml`) | `0.2.0` | `main` | yes |
| **QA snapshot** (`qa-snapshot.yml`) | `0.2.0-QA.20260201143000`, stamped in UTC | any branch | no |

The version is `PayabliCore.version` in `Sources/PayabliSDKCore/PayabliSDKCore.swift`: the version the tree
is heading for, which every module reports. There is no `v` prefix, because SwiftPM reads the tag name as the
version itself.

## Cut a release

1. Open a pull request that sets the install line in `README.md` to the version being released:

   ```swift
   .package(url: "https://github.com/payabli/sdk-ios.git", .upToNextMinor(from: "0.2.0"))
   ```

   `.upToNextMinor` because a minor version can break source before 1.0.
2. Merge it, then run **Release** from `main`.
3. Open a pull request that moves `PayabliCore.version` to the next version.

A published number is never reused. A fix to a release is the next patch.

## Hand someone a QA build

Only when somebody outside the change needs to consume it: run **QA snapshot** from the branch, and give
them the tag it prints to pin exactly:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", exact: "0.2.0-QA.20260201143000")
```

QA tags can be deleted, and `git tag -l '*-QA.*'` lists exactly them. An app of our own that only needs a
commit pins it with `.revision("<sha>")` and needs no tag at all.
