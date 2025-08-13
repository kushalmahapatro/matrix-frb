# Technology Stack

## Frontend
- **Flutter**: Cross-platform UI framework
- **Dart**: Programming language for Flutter
- **Provider**: State management solution
- **Shared Preferences**: Local data persistence

## Backend/Core
- **Rust**: Systems programming language for Matrix SDK integration
- **Matrix SDK**: Rust crate for Matrix protocol implementation
- **Matrix SDK SQLite**: Local storage backend
- **Matrix SDK UI**: UI utilities for Matrix operations
- **Tokio**: Async runtime for Rust
- **Serde**: Serialization/deserialization

## Bridge Technology
- **Flutter Rust Bridge**: Rust-Dart interop (instead of UniFFI)
- **Automatic code generation**: Bindings generated from Rust API

## Development Tools
- **flutter_lints**: Dart/Flutter linting rules
- **build_runner**: Code generation
- **freezed**: Immutable data classes
- **integration_test**: Flutter integration testing

## Fonts & Assets
- **JetBrains Mono**: Monospace font for Matrix terminal aesthetic

## Common Commands

### Setup & Dependencies
```bash
# Install Flutter dependencies
flutter pub get

# Install Rust dependencies
cd rust && cargo build

# Generate Flutter Rust Bridge bindings
flutter_rust_bridge_codegen generate
```

### Development
```bash
# Run the app
flutter run

# Run on specific platform
flutter run -d macos
flutter run -d chrome

# Hot reload is supported during development
```

### Code Generation
```bash
# Generate freezed classes and other code
dart run build_runner build

# Watch for changes and regenerate
dart run build_runner watch
```

### Testing
```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/
```

### Building
```bash
# Build for release
flutter build apk          # Android
flutter build ios          # iOS
flutter build macos        # macOS
flutter build linux        # Linux
flutter build windows      # Windows
flutter build web          # Web
```

### Matrix Server (Development)
```bash
# Start local Synapse server with Docker
docker run -d --name matrix-synapse \
    --mount type=volume,src=matrix_synapse_data,dst=/data \
    -p 8008:8008 \
    matrixdotorg/synapse:latest

# Start Element web client
docker run -d --name matrix-element \
    -p 8080:80 \
    vectorim/element-web:latest
```

## Configuration Files

- `pubspec.yaml`: Flutter dependencies and configuration
- `flutter_rust_bridge.yaml`: Bridge configuration
- `rust/Cargo.toml`: Rust dependencies
- `analysis_options.yaml`: Dart analysis configuration