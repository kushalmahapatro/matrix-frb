# Matrix Flutter App with Flutter Rust Bridge

This project demonstrates how to integrate the Matrix SDK with Flutter using Flutter Rust Bridge instead of UniFFI.

## Overview

This project shows how to:
- Use Flutter Rust Bridge to create bindings between Flutter/Dart and Rust
- Integrate the Matrix SDK (matrix-sdk crate) with Flutter
- Create a Matrix client with login, room management, and messaging capabilities

## Project Structure

```
matrix/
├── lib/
│   ├── main.dart                    # Flutter UI with Matrix client integration
│   └── src/rust/
│       ├── frb_generated.dart       # Auto-generated Flutter Rust Bridge bindings
│       └── api/
│           ├── matrix_client.dart   # Matrix client wrapper
│           ├── matrix_room.dart     # Room management functions
│           └── matrix_message.dart  # Message handling functions
├── rust/
│   ├── src/
│   │   ├── lib.rs                   # Main Rust library entry point
│   │   └── api/
│   │       ├── mod.rs               # API module definitions
│   │       ├── matrix_client.rs     # Matrix client implementation
│   │       ├── matrix_room.rs       # Room operations
│   │       └── matrix_message.rs    # Message operations
│   └── Cargo.toml                   # Rust dependencies
└── flutter_rust_bridge.yaml         # Flutter Rust Bridge configuration
```

## Key Differences from UniFFI

### 1. **Dependency Management**
Instead of using `matrix-sdk-ffi` (which doesn't exist), we use the standard `matrix-sdk` crate:
```toml
[dependencies]
matrix-sdk = "0.13.0"
matrix-sdk-sqlite = "0.13.0"
```

### 2. **API Design**
- **UniFFI**: Uses generated FFI bindings with specific FFI types
- **Flutter Rust Bridge**: Uses Rust types directly with automatic serialization

### 3. **Type Safety**
- **UniFFI**: Requires manual type conversions between FFI and native types
- **Flutter Rust Bridge**: Automatic type conversion with `serde` serialization

### 4. **Async Handling**
- **UniFFI**: Uses callbacks or manual async handling
- **Flutter Rust Bridge**: Native async/await support

## Implementation Details

### Matrix Client Wrapper

The `MatrixClientWrapper` class provides a high-level interface to the Matrix SDK:

```rust
pub struct MatrixClientWrapper {
    client: Arc<Mutex<Option<Client>>>,
    session: Arc<Mutex<Option<Session>>>,
}
```

### Key Features

1. **Authentication**
   - Login with username/password
   - Session management
   - Logout functionality

2. **Room Management**
   - List available rooms
   - Get room information (name, topic, member count)
   - Join/leave rooms

3. **Messaging**
   - Send text messages
   - Retrieve message history
   - Message reactions

4. **Real-time Updates**
   - Sync with Matrix server
   - Handle room events

## Usage Example

```dart
// Get the Matrix client instance
final client = getMatrixClient();

// Login to Matrix
final config = MatrixClientConfig(
  homeserverUrl: 'https://matrix.org',
  username: 'your_username',
  password: 'your_password',
);
final success = client.login(config: config);

// Get rooms
final rooms = client.getRooms();

// Send a message
client.sendMessage(roomId: roomId, content: 'Hello Matrix!');
```

## Local Matrix Server Setup

For development and testing, you can run a local Synapse Matrix server using Docker.

### Quick Setup

1. **Generate Synapse Configuration**
   ```bash
   docker run -it --rm \
       --mount type=volume,src=matrix_synapse_data,dst=/data \
       -e SYNAPSE_SERVER_NAME=localhost \
       -e SYNAPSE_REPORT_STATS=no \
       -e SYNAPSE_ENABLE_REGISTRATION=yes \
       -e SYNAPSE_ENABLE_REGISTRATION_WITHOUT_VERIFICATION=yes \
       matrixdotorg/synapse:latest generate
   ```

2. **Enable Registration** (if needed)
   ```bash
   # Copy the generated config to edit it
   docker run --rm --mount type=volume,src=matrix_synapse_data,dst=/data -v $(pwd):/host alpine:latest cp /data/homeserver.yaml /host/homeserver_generated.yaml
   
   # Edit the file to add registration settings
   # Add these lines to homeserver_generated.yaml:
   # enable_registration: true
   # enable_registration_without_verification: true
   
   # Copy the updated config back
   docker run --rm --mount type=volume,src=matrix_synapse_data,dst=/data -v $(pwd):/host alpine:latest cp /host/homeserver_generated.yaml /data/homeserver.yaml
   ```

3. **Start Synapse Server**
   ```bash
   docker run -d --name matrix-synapse \
       --mount type=volume,src=matrix_synapse_data,dst=/data \
       -p 8008:8008 \
       matrixdotorg/synapse:latest run \
       -m synapse.app.homeserver \
       --config-path=/data/homeserver.yaml
   ```

4. **Start Element Web Client** (optional)
   ```bash
   docker run -d --name matrix-element \
       -p 8080:80 \
       --env ELEMENT_CONFIG='{"default_server_config":{"m.homeserver":{"base_url":"http://localhost:8008"}},"disable_guests":true,"brand":"Local Matrix"}' \
       vectorim/element-web:latest
   ```

### Server URLs
- **Synapse API**: http://localhost:8008
- **Element Web UI**: http://localhost:8080

### Test Registration
```bash
curl -s -X POST http://localhost:8008/_matrix/client/r0/register \
    -H "Content-Type: application/json" \
    -d '{"auth": {"type": "m.login.dummy"}, "initial_device_display_name": "test", "username": "testuser", "password": "testpass"}'
```

### Stop Servers
```bash
docker stop matrix-synapse matrix-element
docker rm matrix-synapse matrix-element
```

## Building and Running

1. **Install Dependencies**
   ```bash
   flutter pub get
   cd rust && cargo build
   ```

2. **Generate Bindings**
   ```bash
   flutter_rust_bridge_codegen generate
   ```

3. **Run the App**
   ```bash
   flutter run
   ```

## Configuration

The `flutter_rust_bridge.yaml` file configures the code generation:

```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

## Benefits of Flutter Rust Bridge over UniFFI

1. **Simpler Setup**: No need for complex FFI type definitions
2. **Better Type Safety**: Automatic serialization with `serde`
3. **Easier Debugging**: Direct Rust types in Dart
4. **Better Performance**: Less overhead from FFI conversions
5. **More Flexible**: Can use any Rust crate, not just FFI-compatible ones

## Future Enhancements

- [ ] End-to-end encryption support
- [ ] File upload/download
- [ ] Voice/video calling
- [ ] Push notifications
- [ ] Offline message caching
- [ ] Room creation and management
- [ ] User profile management

## Contributing

This is a demonstration project. For production use, consider:
- Adding proper error handling
- Implementing retry logic
- Adding unit tests
- Security hardening
- Performance optimization

## License

This project is for educational purposes. The Matrix SDK is licensed under the Apache 2.0 License.
