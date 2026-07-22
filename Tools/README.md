# Development tools

Development-only Swift package dependencies live here so that CocoaMQTT users do
not resolve or download them.

Run SwiftLint from the repository root with:

```sh
Tools/lint.sh
```

The package lock file pins the SwiftLint plugin version, making the local command
and CI use the same tool.
