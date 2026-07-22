# Development tools

Development-only Swift package dependencies live here so that CocoaMQTT users do
not resolve or download them.

Run SwiftLint from the repository root with:

```sh
Tools/lint.sh
```

The package lock file pins the SwiftLint plugin version, making the local command
and CI use the same tool.

Swift 5.9 or newer is required to run this tooling package because
SwiftLintPlugins 0.63.2 itself requires SwiftPM 5.9. This does not change the
main CocoaMQTT package's Swift 5.7 minimum.
