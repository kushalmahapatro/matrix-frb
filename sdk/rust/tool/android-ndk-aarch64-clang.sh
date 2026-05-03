#!/usr/bin/env sh
# Rust's linker for `aarch64-linux-android`. Host `cc` on macOS invokes Apple `ld`, which
# rejects GNU flags like `-Wl,--version-script=...` and breaks `cdylib` crates (e.g. pdfium-render).
# Delegates to the same NDK clang as `tool/ndk-bin/aarch64-linux-android-clang`.
exec "$(dirname "$0")/android-ndk-exec.sh" clang "$@"
