#!/usr/bin/env sh
# Shared resolver for NDK LLVM tools. The NDK ships `aarch64-linux-android35-clang`, but
# cc-rs / openssl-sys default to the unsuffixed name `aarch64-linux-android-clang` on PATH.
set -e
tool="$1"
shift
ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${NDK_HOME:-}}}"
if [ -z "$ndk" ]; then
  echo "android-ndk-exec.sh: set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) to your NDK root" >&2
  exit 1
fi
host="${ANDROID_NDK_HOST:-}"
if [ -z "$host" ]; then
  case "$(uname -s)" in
    Darwin)
      if [ -d "$ndk/toolchains/llvm/prebuilt/darwin-arm64" ]; then
        host=darwin-arm64
      else
        host=darwin-x86_64
      fi
      ;;
    Linux) host=linux-x86_64 ;;
    MINGW* | MSYS* | CYGWIN*) host=windows-x86_64 ;;
    *)
      echo "android-ndk-exec.sh: unknown host OS; set ANDROID_NDK_HOST" >&2
      exit 1
      ;;
  esac
fi
api="${ANDROID_NDK_API_LEVEL:-35}"
bindir="$ndk/toolchains/llvm/prebuilt/$host/bin"
case "$tool" in
  clang)
    exe="$bindir/aarch64-linux-android${api}-clang"
    ;;
  clangxx)
    exe="$bindir/aarch64-linux-android${api}-clang++"
    ;;
  ar)
    exe="$bindir/llvm-ar"
    ;;
  ranlib)
    exe="$bindir/llvm-ranlib"
    ;;
  *)
    echo "android-ndk-exec.sh: unknown tool: $tool" >&2
    exit 1
    ;;
esac
if [ ! -x "$exe" ]; then
  echo "android-ndk-exec.sh: missing executable: $exe" >&2
  exit 1
fi
exec "$exe" "$@"
