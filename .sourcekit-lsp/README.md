# sourcekit-lsp configuration

`config.json` here tells [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp)
that this Swift package targets the **iOS Simulator**, not the host
macOS triple it would otherwise default to. This silences a stream of
false-positive availability warnings in non-Xcode IDEs (Cursor, VS
Code, Neovim) that consume sourcekit-lsp directly:

- `'ObservableObject' is only available in macOS 10.15 or newer`
- `'data(for:delegate:)' is only available in macOS 12.0 or newer`
- `'AsyncStream' is only available in macOS 10.15 or newer`
- …and similar for `actor`, `@MainActor`, `Task`, etc.

These warnings are noise — `Package.swift` declares the SDK as
**iOS-only** (`.iOS("16.7")`), so build, CI, and release all target
iOS via `xcodebuild` and never see them. They only appear in the IDE
because sourcekit-lsp falls back to the host triple (`arm64-apple-macosx`)
when no platform is supplied. Setting the triple here aligns the IDE
analysis with the actual deployment target.

## Format

```json
{
  "swiftPM": {
    "triple": "arm64-apple-ios16.7-simulator"
  }
}
```

The `triple` field is supported by SourceKit-LSP shipped with Swift
5.10+. If you're on an older toolchain and the field is ignored, use
the legacy `swiftPM.swiftCompilerFlags` form instead:

```json
{
  "swiftPM": {
    "swiftCompilerFlags": ["-target", "arm64-apple-ios16.7-simulator"]
  }
}
```

## Editor-specific notes

- **Cursor / VS Code with the Swift extension** — picks up
  `.sourcekit-lsp/config.json` automatically on workspace open. If the
  warnings persist, restart the language server (Cmd+Shift+P →
  "Swift: Restart LSP Server") so it re-reads the config.
- **Xcode** — ignores this file; Xcode drives sourcekit through the
  active scheme's destination instead. Selecting an iOS Simulator
  destination already silences the warnings, so no IDE-side config is
  needed.
- **Neovim with sourcekit-lsp** — picks up the file via the standard
  workspace root discovery, no extra config required.

## Why not declare `.macOS` in `Package.swift`?

We tried. Adding `.macOS(.v12)` silences the IDE warnings but breaks
`swift build` on a macOS host because the vendored
`PayabliCardReaderCore` source imports `ProximityReader`, which is
iOS-only. The vendored source is byte-identical to upstream
(`ThirdParty/PayabliCardReaderCoreSource/README.md` documents the
contract), so we can't `#if os(iOS)` around the import. SPM also
doesn't allow a `condition: .when(platforms: [.iOS])` on a `.target()`
or `.library()` itself — only on the *dependencies* between targets.

The `.sourcekit-lsp/config.json` approach side-steps the whole
problem: the IDE evaluates code as iOS, but the SPM platform list
remains iOS-only so no target ever attempts a macOS build.
