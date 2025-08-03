# Rust Logging Solution for Flutter Matrix App

## Problem
Rust logs (like `println!`, `log::info!`, etc.) were not appearing in the Flutter console, making debugging difficult when working with Flutter Rust Bridge.

## Solution Overview
This solution implements a comprehensive logging system that forwards Rust logs to the Flutter console through multiple approaches:

### 1. Rust Logging Dependencies
Added logging dependencies to `rust/Cargo.toml`:
```toml
log = "0.4"
env_logger = "0.10"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

### 2. Rust Logging Initialization
In `rust/src/api/simple.rs`:
- Added logging initialization in `init_app()` function
- Created `init_rust_logging()` function to set up tracing and env_logger
- Added `log_message()` bridge function for manual logging

### 3. Matrix Client Logging
In `rust/src/api/matrix_client.rs`:
- Added logging statements to key functions (`init_client`, `login`, etc.)
- Logs include info, debug, warn, and error levels
- Provides detailed logging for debugging Matrix operations

### 4. Flutter Logging Service
In `lib/src/rust/api/simple.dart`:
- Created `RustLoggingService` class
- Handles different log levels with appropriate formatting
- Includes timestamps and visual indicators for different log types

### 5. Custom Flutter Rust Bridge Handler
In `lib/src/rust/frb_generated.dart`:
- Added `CustomLoggingHandler` class
- Automatically forwards Rust bridge logs to Flutter console
- Integrated into the RustLib initialization

### 6. App Initialization
In `lib/main.dart` and `lib/src/splash_screen.dart`:
- Initialize Rust logging on app startup
- Test logging functionality during authentication check

## Usage Examples

### From Rust Code
```rust
use log::{info, warn, error, debug};

// Log different levels
info!("Matrix client initialized successfully");
debug!("Storage path: {}", config.storage_path);
warn!("Connection timeout, retrying...");
error!("Failed to build Matrix client: {}", e);

// Manual logging through bridge
log_message("info".to_string(), "Custom message from Rust".to_string());
```

### From Flutter Code
```dart
// Initialize logging
await RustLoggingService.initializeLogging();

// Log through bridge function
logMessage(level: "info", message: "Starting Matrix client initialization");
```

## Log Levels and Formatting

### Log Levels
- **DEBUG**: Only shown in debug mode
- **INFO**: Standard information messages
- **WARN**: Warning messages with ⚠️ indicator
- **ERROR**: Error messages with ❌ indicator

### Log Format
```
[RUST] [INFO] 2024-01-15T10:30:45.123Z: Matrix client initialized successfully
[RUST_BRIDGE] Flutter Rust Bridge message
```

## Environment Variables

You can control Rust logging levels by setting the `RUST_LOG` environment variable:
- `RUST_LOG=debug` - Show all logs
- `RUST_LOG=info` - Show info and above (default)
- `RUST_LOG=warn` - Show warnings and errors only
- `RUST_LOG=error` - Show errors only

## Testing the Logging

1. **Build the project**:
   ```bash
   flutter clean
   flutter pub get
   cd rust && cargo build
   cd .. && flutter run
   ```

2. **Check Flutter console** for logs like:
   ```
   [FLUTTER] Initializing Matrix app with Rust logging...
   [RUST] [INFO] 2024-01-15T10:30:45.123Z: Rust logging system initialized
   [RUST] [INFO] 2024-01-15T10:30:45.124Z: Rust logging initialized successfully
   [RUST] [INFO] 2024-01-15T10:30:45.125Z: Starting Matrix client initialization
   [RUST] [INFO] 2024-01-15T10:30:45.126Z: Initializing Matrix client with homeserver: http://localhost:8008
   ```

## Troubleshooting

### Logs Still Not Appearing
1. Check that `RustLib.init()` is called with the custom handler
2. Verify that logging dependencies are properly added to Cargo.toml
3. Ensure the Rust code is recompiled after changes
4. Check that the app is running in debug mode

### Performance Considerations
- Debug logs are only shown in debug mode to avoid performance impact
- Logging is asynchronous and won't block the UI
- Consider using appropriate log levels in production

### Platform-Specific Notes
- **iOS/Android**: Logs appear in Flutter console and device logs
- **Web**: Logs appear in browser console
- **Desktop**: Logs appear in terminal/console

## Benefits

1. **Debugging**: Easy to trace Rust operations in Flutter console
2. **Error Tracking**: Clear error messages with context
3. **Performance Monitoring**: Track Matrix operations timing
4. **Development Experience**: Better visibility into Rust-Flutter bridge
5. **Production Ready**: Configurable log levels for different environments

## Future Enhancements

1. **Structured Logging**: Add JSON formatting for better log parsing
2. **Log Persistence**: Save logs to file for debugging
3. **Remote Logging**: Send logs to external services
4. **Log Filtering**: Filter logs by module/component
5. **Performance Metrics**: Add timing information to operations 