# Native media: Pdfium, FFmpeg, environment variables

The Rust SDK uses these for **PDF thumbnails**, **video frame thumbnails / transcode**, and related features:

| Variable | Purpose |
|----------|---------|
| `PDFIUM_DYNAMIC_LIB_PATH` | Directory containing `libpdfium.dylib` (macOS), `libpdfium.so` (Linux), etc. |
| `MATRIX_PDFIUM_DIR` | Extra directory to search for the same library (often set to the same path as above). |
| `MATRIX_FFMPEG_PATH` | Full path to the `ffmpeg` executable (optional if `ffmpeg` is on `PATH`). |

Flutter can also call `setNativeMediaEnv` at startup; see `AppConfig` / `FilePathService.resolveNativeMediaRustPaths` in the app.

## Native hook (`build.dart`)

When the SDK’s **hook** runs `cargo` (see `sdk/hook/build.dart`), it:

1. Runs **`native_media_bootstrap.dart`**: downloads **host** Pdfium ([bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries)) into `sdk/.matrix-sdk/native/pdfium/lib/` when missing, and copies **`ffmpeg`** from `PATH` / common install paths into `sdk/.matrix-sdk/native/bin/` when found.
2. Passes **`extraCargoEnvironmentVariables`** from `matrix_native_media_env.dart` (`matrixNativeMediaCargoEnv(packageRoot: …)`), including those directories plus any existing `PDFIUM_*` / `MATRIX_FFMPEG_PATH` / `$HOME/.matrix-sdk/…` overrides.

**Flutter assets:** `matrix_sdk` declares those folders as assets so **desktop** apps can copy binaries into application support on startup (`FilePathService`).

**Native code assets:** After the Rust [CodeAsset] is emitted, the hook adds a second [CodeAsset] for **Pdfium** (`native/pdfium_dl.dart` id) via `DynamicLoadingBundled`, using the archive that matches the hook’s **target OS/architecture** (Android/iOS/macOS/Windows/Linux) so the correct `.so` / `.dylib` / `.dll` is bundled with the app.

**Mobile** host bootstrap still uses **host** Pdfium under `.matrix-sdk/native/` for local tooling; set `MATRIX_HOOK_SKIP_NATIVE_MEDIA_BOOTSTRAP=1` to skip downloads entirely (e.g. CI).

This affects the **cargo build subprocess** and **desktop** runtime when assets are present. Runtime still uses `setNativeMediaEnv` after materialization (or `--dart-define` overrides).

## macOS (recommended)

1. **FFmpeg** (Homebrew):

   ```bash
   brew install ffmpeg
   ```

2. **Pdfium + env file** (downloads [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) to `~/.matrix-sdk/native/pdfium/`):

   ```bash
   cd /path/to/matrix-rust-dart-sdk
   chmod +x sdk/tool/setup_native_media_env_macos.sh
   ./sdk/tool/setup_native_media_env_macos.sh
   ```

3. **Load variables in every shell**:

   ```bash
   echo 'source "$HOME/.matrix-sdk/native/env.sh"' >> ~/.zshrc
   source ~/.zshrc
   ```

### GUI apps (Flutter / Xcode)

`.zshrc` is **not** read when you click Run in the IDE. Options:

- Start the IDE from a terminal where you already `source`d `env.sh`, or  
- Add the same three variables under **Product → Scheme → Edit Scheme → Run → Environment Variables** in Xcode, or  
- Use `--dart-define=…` for the app (see `AppConfig` in the Flutter app).

## Linux

- Install `ffmpeg` with your package manager and ensure it is on `PATH`, or set `MATRIX_FFMPEG_PATH` to the binary.
- Download the matching `pdfium-linux-*` tgz from [pdfium-binaries releases](https://github.com/bblanchon/pdfium-binaries/releases), extract it, and set `PDFIUM_DYNAMIC_LIB_PATH` / `MATRIX_PDFIUM_DIR` to the directory that contains `libpdfium.so` (usually the `lib` folder inside the archive).

## Android / iOS (Flutter app)

**Pdfium:** The hook’s Pdfium **CodeAsset** places the library next to other native libs. At runtime the app prefers:

- **Android:** `ApplicationInfo.nativeLibraryDir` (via `MethodChannel` `dev.inve.matrixchat/native_media` → `getNativeLibraryDir`) when `libpdfium.so` is present there; otherwise materialized assets under application support.
- **iOS:** `dirname(Platform.resolvedExecutable)/Frameworks` when `libpdfium.dylib` exists; otherwise materialized assets.

**FFmpeg (Android):** For Android targets the hook may download a **Linux static** build from [eugeneware/ffmpeg-static](https://github.com/eugeneware/ffmpeg-static) (`ffmpeg_android_arm64`, etc.) into `.matrix-sdk/native/bin/`. That binary is **best-effort**: it is built for glibc/Linux and may not run on all Android devices; if it fails, set `MATRIX_FFMPEG_PATH` / install a device-appropriate `ffmpeg`, or rely on features that do not need subprocess FFmpeg.

**FFmpeg (iOS):** The app does **not** bundle a subprocess `ffmpeg` by default; use `--dart-define` / a custom pipeline if you need it.

## Regenerate FRB bindings

After changing Rust API modules:

```bash
./sdk/tool/regenerate_fr_bindings.sh
```
