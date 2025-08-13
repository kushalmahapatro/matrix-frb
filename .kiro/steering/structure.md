# Project Structure

## Root Level Organization

```
matrix/
├── lib/                    # Flutter/Dart source code
├── rust/                   # Rust source code and Matrix SDK integration
├── android/                # Android-specific configuration
├── ios/                    # iOS-specific configuration
├── macos/                  # macOS-specific configuration
├── linux/                  # Linux-specific configuration
├── windows/                # Windows-specific configuration
├── web/                    # Web-specific configuration
├── fonts/                  # Custom fonts (JetBrains Mono)
├── synapse/                # Local Matrix server configuration
└── test/                   # Test files
```

## Flutter Code Structure (`lib/`)

```
lib/
├── main.dart               # App entry point and initialization
└── src/
    ├── extensions/         # Dart extension methods
    ├── rust/              # Generated Flutter Rust Bridge bindings
    │   ├── api/           # Generated Dart API wrappers
    │   ├── frb_generated.dart
    │   └── logging_handler.dart
    ├── theme/             # UI theming and styling
    │   ├── matrix_theme.dart
    │   ├── theme_provider.dart
    │   └── theme_switcher.dart
    ├── *.dart             # Screen/service files (login, home, timeline, etc.)
    └── logging_service.dart
```

## Rust Code Structure (`rust/`)

```
rust/
├── Cargo.toml             # Rust dependencies and configuration
├── matrix-rust-sdk/       # Git submodule of Matrix Rust SDK
└── src/
    ├── lib.rs             # Main Rust library entry point
    ├── frb_generated.rs   # Generated Flutter Rust Bridge code
    └── api/               # Public API modules exposed to Flutter
        ├── mod.rs         # Module declarations
        ├── init.rs        # Initialization functions
        ├── logger.rs      # Logging integration
        ├── matrix_client.rs # Matrix client wrapper
        ├── matrix_room.rs   # Room operations
        ├── matrix_message.rs # Message handling
        ├── platform.rs    # Platform-specific code
        └── tracing.rs     # Tracing/logging configuration
```

## Key Architectural Patterns

### Flutter Rust Bridge Integration
- Rust API modules in `rust/src/api/` define the interface
- Flutter bindings auto-generated in `lib/src/rust/api/`
- Async operations supported natively between Rust and Dart

### State Management
- Provider pattern for theme management
- Services for Matrix operations and logging
- Shared preferences for persistence

### UI Architecture
- Screen-based organization (login_screen.dart, home_screen.dart, etc.)
- Centralized theming with Matrix green terminal aesthetic
- Custom extensions for common operations

### Matrix SDK Integration
- Wrapper classes around Matrix SDK in Rust
- Session management and persistence
- Real-time sync handling

## File Naming Conventions

### Dart Files
- `snake_case.dart` for all Dart files
- `*_screen.dart` for UI screens
- `*_service.dart` for business logic services
- `*_provider.dart` for state management
- `*_theme.dart` for theming

### Rust Files
- `snake_case.rs` for all Rust files
- API modules match their Dart counterparts
- `mod.rs` for module declarations

## Configuration Files

- `pubspec.yaml`: Flutter dependencies and app metadata
- `flutter_rust_bridge.yaml`: Bridge configuration
- `analysis_options.yaml`: Dart linting rules
- `rust/Cargo.toml`: Rust dependencies
- Platform-specific configs in respective folders

## Generated Code

- `lib/src/rust/frb_generated.dart`: Auto-generated Flutter bindings
- `rust/src/frb_generated.rs`: Auto-generated Rust bindings
- Never edit generated files directly - regenerate with `flutter_rust_bridge_codegen generate`