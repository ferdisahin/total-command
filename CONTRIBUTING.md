# Contributing

Total Command is licensed under GPL-3.0-only. Contributions are accepted under the same license. Preserve notices and describe your modifications.

Build requirements: macOS 13+, Xcode command line tools. No third-party packages are needed.

Run `./test.sh` and `./build.sh` before submitting a pull request. For both Mac architectures, run `BUILD_ARCHS="arm64 x86_64" ./build.sh`.

For changes to file operations, include tests for interrupted work, existing destinations, symlinks and names containing spaces/non-ASCII characters. Keep file deletion recoverable through Trash. Describe observable behavior and manual UI validation.

Do not commit signing certificates, private keys, notarization credentials, user paths, generated app bundles or release artifacts. Signing is performed locally by the maintainer.
