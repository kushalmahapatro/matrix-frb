# Code Conventions & Style Guide

## Dart/Flutter Conventions

### File Organization
- Use `snake_case` for all file names
- Group related files in folders (e.g., `theme/`, `extensions/`)
- Suffix files by type: `*_screen.dart`, `*_service.dart`, `*_provider.dart`
- Keep screens in root `src/` directory, utilities in subdirectories

### Code Style
- Follow `flutter_lints` rules (configured in `analysis_options.yaml`)
- Use `const` constructors wherever possible for performance
- Prefer `final` over `var` for immutable variables
- Use meaningful variable names, avoid abbreviations

### State Management
- Use Provider pattern for app-wide state (theme, authentication)
- Use StatefulWidget for local component state
- Services should be stateless and expose async methods
- Use `Consumer<T>` or `context.read<T>()` for Provider access

### UI Patterns
- All screens should extend `StatefulWidget` for lifecycle management
- Use `SafeArea` for proper screen boundaries
- Implement `WidgetsBindingObserver` for platform brightness changes
- Use `MatrixTheme` constants for consistent styling

### Error Handling
- Always handle async operations with try-catch
- Use `mounted` checks before `setState` in async callbacks
- Display user-friendly error messages via status text or snackbars
- Log errors using `LoggingService` for debugging

## Rust Conventions

### File Organization
- Keep all public API in `rust/src/api/` modules
- Use `mod.rs` to declare module structure
- Match Rust module names with Dart API counterparts
- Separate concerns: client, rooms, messages, etc.

### Code Style
- Use `snake_case` for functions and variables
- Use `PascalCase` for structs and enums
- Add `#[derive(Debug, Clone, Serialize, Deserialize)]` to data structures
- Use `Result<T, String>` for error handling in public APIs

### Async Patterns
- Use `tokio::task::block_in_place` for sync-to-async conversion
- Maintain global runtime with `GLOBAL_RUNTIME`
- Use `Arc<Mutex<T>>` for shared state across async boundaries
- Always handle `await` results with proper error propagation

### Matrix SDK Integration
- Wrap Matrix SDK types in custom structs for Flutter compatibility
- Use global static variables for client state management
- Implement proper session persistence with JSON serialization
- Handle Matrix errors gracefully and convert to user-friendly messages

## Flutter Rust Bridge Patterns

### Data Types
- Use `#[derive(Serialize, Deserialize)]` for all data structures
- Prefer simple types (String, u64, bool) over complex Rust types
- Use `Option<T>` for nullable fields
- Convert Matrix SDK types to bridge-compatible types

### Function Signatures
- Keep public functions simple with basic parameter types
- Use `Result<T, String>` return types for error handling
- Avoid complex generics in public API
- Use `StreamSink<T>` for real-time data streams

### Code Generation
- Never edit generated files (`frb_generated.*`)
- Regenerate bindings after API changes: `flutter_rust_bridge_codegen generate`
- Update `flutter_rust_bridge.yaml` when adding new modules
- Test bindings after regeneration

## Logging & Debugging

### Logging Patterns
- Use `LoggingService` in Dart for consistent logging
- Use `log_info`, `log_error` functions in Rust
- Include context in log messages (function name, operation)
- Log important state changes and errors

### Debug Information
- Add debug prints for async operation status
- Log Matrix SDK responses for troubleshooting
- Include timestamps in status messages
- Use structured logging for better debugging

## Testing Conventions

### Unit Tests
- Test business logic in services
- Mock external dependencies (Matrix SDK calls)
- Use descriptive test names: `should_login_successfully_with_valid_credentials`
- Group related tests in `group()` blocks

### Integration Tests
- Test complete user flows (login → rooms → messages)
- Use real Matrix server for integration tests
- Clean up test data after each test
- Test error scenarios and edge cases

## Performance Guidelines

### Flutter Performance
- Use `const` constructors for static widgets
- Implement `build` method efficiently, avoid heavy computations
- Use `ListView.builder` for large lists
- Cache expensive operations in services

### Rust Performance
- Use `Arc<Mutex<T>>` judiciously to avoid lock contention
- Prefer `tokio::spawn` for independent async tasks
- Cache Matrix client instances globally
- Use efficient data structures for message storage

## Security Considerations

### Authentication
- Store session data securely using platform keychain
- Never log passwords or sensitive tokens
- Implement proper logout that clears all stored data
- Use HTTPS for all Matrix server communications

### Data Handling
- Encrypt local database with passphrase
- Validate all user inputs before processing
- Sanitize display content to prevent injection
- Handle Matrix events securely without exposing internals