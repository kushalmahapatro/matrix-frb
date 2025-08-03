# Matrix SDK Integration with Flutter Rust Bridge

This document explains how to integrate the Matrix SDK with Flutter using Flutter Rust Bridge instead of UniFFI.

## Overview

The Matrix SDK FFI bindings from the [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk) repository are designed to work with UniFFI. However, this project demonstrates how to achieve the same functionality using Flutter Rust Bridge, which offers several advantages.

## Key Differences from UniFFI Approach

### 1. **Dependency Management**

**UniFFI Approach:**
```toml
[dependencies]
matrix-sdk-ffi = "0.8.0"  # This crate doesn't exist
```

**Flutter Rust Bridge Approach:**
```toml
[dependencies]
matrix-sdk = "0.13.0"           # Use the actual Matrix SDK
matrix-sdk-sqlite = "0.13.0"    # SQLite storage backend
flutter_rust_bridge = "2.11.1"  # Flutter Rust Bridge
serde = { version = "1.0", features = ["derive"] }  # Serialization
anyhow = "1.0"                  # Error handling
tokio = { version = "1.0", features = ["full"] }    # Async runtime
```

### 2. **API Design**

**UniFFI:** Requires specific FFI-compatible types and manual conversions
**Flutter Rust Bridge:** Uses native Rust types with automatic serialization

### 3. **Type Safety**

**UniFFI:** Manual type conversions between FFI and native types
**Flutter Rust Bridge:** Automatic type conversion with `serde` serialization

### 4. **Async Handling**

**UniFFI:** Uses callbacks or manual async handling
**Flutter Rust Bridge:** Native async/await support

## Implementation

### 1. Rust Side Implementation

#### Matrix Client Wrapper (`rust/src/api/matrix_client.rs`)

```rust
use matrix_sdk::{Client, ClientBuilder, Session, Room};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixClientConfig {
    pub homeserver_url: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixRoomInfo {
    pub room_id: String,
    pub name: Option<String>,
    pub topic: Option<String>,
    pub member_count: u32,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixMessage {
    pub event_id: String,
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
}

pub struct MatrixClientWrapper {
    client: Arc<Mutex<Option<Client>>>,
    session: Arc<Mutex<Option<Session>>>,
}

impl MatrixClientWrapper {
    pub fn new() -> Self {
        Self {
            client: Arc::new(Mutex::new(None)),
            session: Arc::new(Mutex::new(None)),
        }
    }

    
    pub async fn login(&self, config: MatrixClientConfig) -> Result<bool> {
        let client = Client::builder()
            .homeserver_url(&config.homeserver_url)
            .build()
            .await?;

        let session = client
            .login_username(&config.username, &config.password)
            .initial_device_display_name("Matrix Flutter App")
            .await?;

        *self.client.lock().await = Some(client);
        *self.session.lock().await = Some(session);
        Ok(true)
    }

    
    pub async fn get_rooms(&self) -> Result<Vec<MatrixRoomInfo>> {
        let client = self.client.lock().await;
        let client = client.as_ref().ok_or_else(|| {
            anyhow::anyhow!("Client not initialized. Please login first.")
        })?;

        // Sync to get the latest room list
        let sync_settings = SyncSettings::default().token(client.sync_token().await);
        client.sync_once(sync_settings).await?;

        let rooms = client.rooms();
        let mut room_infos = Vec::new();
        
        for room in rooms {
            let room_info = MatrixRoomInfo {
                room_id: room.room_id().to_string(),
                name: room.name().map(|s| s.to_string()),
                topic: room.topic().map(|s| s.to_string()),
                member_count: room.member_count(),
                is_encrypted: room.is_encrypted(),
            };
            room_infos.push(room_info);
        }
        
        Ok(room_infos)
    }

    
    pub async fn send_message(&self, room_id: String, content: String) -> Result<String> {
        let client = self.client.lock().await;
        let client = client.as_ref().ok_or_else(|| {
            anyhow::anyhow!("Client not initialized. Please login first.")
        })?;

        let room = client.get_room(&room_id).ok_or_else(|| {
            anyhow::anyhow!("Room not found: {}", room_id)
        })?;

        let response = room.send(
            matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(&content)
        ).await?;
        Ok(response.event_id.to_string())
    }

    
    pub async fn get_messages(&self, room_id: String, limit: u32) -> Result<Vec<MatrixMessage>> {
        let client = self.client.lock().await;
        let client = client.as_ref().ok_or_else(|| {
            anyhow::anyhow!("Client not initialized. Please login first.")
        })?;

        let room = client.get_room(&room_id).ok_or_else(|| {
            anyhow::anyhow!("Room not found: {}", room_id)
        })?;

        let timeline = room.timeline().await;
        let events = timeline.events_before(None, limit as usize).await?;
        
        let mut messages = Vec::new();
        for event in events {
            if let Some(message_event) = event.as_message() {
                let message = MatrixMessage {
                    event_id: event.event_id().to_string(),
                    sender: event.sender().to_string(),
                    content: message_event.body().to_string(),
                    timestamp: event.timestamp().as_secs(),
                };
                messages.push(message);
            }
        }
        
        Ok(messages)
    }

    
    pub async fn is_logged_in(&self) -> bool {
        self.client.lock().await.is_some()
    }
}

// Global instance for Flutter to use
static MATRIX_CLIENT: once_cell::sync::Lazy<Arc<MatrixClientWrapper>> = 
    once_cell::sync::Lazy::new(|| Arc::new(MatrixClientWrapper::new()));


pub async fn get_matrix_client() -> Arc<MatrixClientWrapper> {
    MATRIX_CLIENT.clone()
}
```

### 2. Flutter Side Usage

#### Basic Usage Example

```dart
import 'package:matrix/src/rust/frb_generated.dart';

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
final eventId = client.sendMessage(
  roomId: roomId,
  content: 'Hello Matrix!'
);

// Get messages
final messages = client.getMessages(roomId: roomId, limit: 50);
```

#### Complete Flutter Widget Example

```dart
import 'package:flutter/material.dart';
import 'package:matrix/src/rust/frb_generated.dart';

class MatrixChatWidget extends StatefulWidget {
  @override
  _MatrixChatWidgetState createState() => _MatrixChatWidgetState();
}

class _MatrixChatWidgetState extends State<MatrixChatWidget> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  
  bool _isLoggedIn = false;
  List<MatrixRoomInfo> _rooms = [];
  List<MatrixMessage> _messages = [];
  String? _selectedRoomId;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() {
    final client = getMatrixClient();
    final isLoggedIn = client.isLoggedIn();
    setState(() {
      _isLoggedIn = isLoggedIn;
    });
  }

  void _login() async {
    final client = getMatrixClient();
    final config = MatrixClientConfig(
      homeserverUrl: 'https://matrix.org',
      username: _usernameController.text,
      password: _passwordController.text,
    );

    final success = client.login(config: config);
    
    if (success) {
      setState(() {
        _isLoggedIn = true;
      });
      _loadRooms();
    }
  }

  void _loadRooms() {
    final client = getMatrixClient();
    final rooms = client.getRooms();
    setState(() {
      _rooms = rooms;
    });
  }

  void _loadMessages(String roomId) {
    final client = getMatrixClient();
    final messages = client.getMessages(roomId: roomId, limit: 50);
    setState(() {
      _messages = messages;
      _selectedRoomId = roomId;
    });
  }

  void _sendMessage() {
    if (_selectedRoomId == null || _messageController.text.isEmpty) return;

    final client = getMatrixClient();
    client.sendMessage(
      roomId: _selectedRoomId!,
      content: _messageController.text,
    );
    _messageController.clear();
    _loadMessages(_selectedRoomId!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Matrix Chat')),
      body: _isLoggedIn ? _buildChatInterface() : _buildLoginForm(),
    );
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          ElevatedButton(
            onPressed: _login,
            child: Text('Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInterface() {
    return Row(
      children: [
        // Room list
        Expanded(
          flex: 1,
          child: ListView.builder(
            itemCount: _rooms.length,
            itemBuilder: (context, index) {
              final room = _rooms[index];
              return ListTile(
                title: Text(room.name ?? room.roomId),
                onTap: () => _loadMessages(room.roomId),
              );
            },
          ),
        ),
        // Messages
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return ListTile(
                      title: Text(message.sender),
                      subtitle: Text(message.content),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(hintText: 'Type a message...'),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

## Configuration

### Flutter Rust Bridge Configuration (`flutter_rust_bridge.yaml`)

```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

### Cargo Configuration (`rust/Cargo.toml`)

```toml
[package]
name = "rust_lib_matrix"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
flutter_rust_bridge = "=2.11.1"
matrix-sdk = "0.13.0"
matrix-sdk-sqlite = "0.13.0"
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
anyhow = "1.0"
url = "2.0"
once_cell = "1.0"
futures = "0.3"

[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(frb_expand)'] }
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

## Benefits of Flutter Rust Bridge over UniFFI

1. **Simpler Setup**: No need for complex FFI type definitions
2. **Better Type Safety**: Automatic serialization with `serde`
3. **Easier Debugging**: Direct Rust types in Dart
4. **Better Performance**: Less overhead from FFI conversions
5. **More Flexible**: Can use any Rust crate, not just FFI-compatible ones
6. **Native Async Support**: Direct async/await without callbacks
7. **Better Error Handling**: Uses `anyhow` for comprehensive error handling

## Advanced Features

### 1. End-to-End Encryption

The Matrix SDK supports end-to-end encryption out of the box. You can extend the wrapper to include encryption features:

```rust

pub async fn enable_encryption(&self) -> Result<bool> {
    let client = self.client.lock().await;
    let client = client.as_ref().ok_or_else(|| {
        anyhow::anyhow!("Client not initialized.")
    })?;

    // Enable encryption
    client.encryption().enable().await?;
    Ok(true)
}
```

### 2. File Upload/Download

```rust

pub async fn upload_file(&self, room_id: String, file_path: String) -> Result<String> {
    let client = self.client.lock().await;
    let client = client.as_ref().ok_or_else(|| {
        anyhow::anyhow!("Client not initialized.")
    })?;

    let room = client.get_room(&room_id).ok_or_else(|| {
        anyhow::anyhow!("Room not found: {}", room_id)
    })?;

    // Upload file
    let response = room.send_attachment(&file_path).await?;
    Ok(response.event_id.to_string())
}
```

### 3. Real-time Event Handling

```rust

pub async fn start_sync(&self) -> Result<()> {
    let client = self.client.lock().await;
    let client = client.as_ref().ok_or_else(|| {
        anyhow::anyhow!("Client not initialized.")
    })?;

    // Start continuous sync
    client.start_sync().await?;
    Ok(())
}
```

## Troubleshooting

### Common Issues

1. **Build Errors**: Ensure all dependencies are correctly specified in `Cargo.toml`
2. **Type Errors**: Regenerate bindings with `flutter_rust_bridge_codegen generate`
3. **Runtime Errors**: Check that the Matrix client is properly initialized before use
4. **Network Issues**: Verify homeserver URL and network connectivity

### Debug Tips

1. Use `println!` in Rust code for debugging
2. Check Flutter console for error messages
3. Verify Matrix SDK version compatibility
4. Test with a simple Matrix homeserver first

## Conclusion

This approach provides a robust, type-safe, and performant way to integrate the Matrix SDK with Flutter applications. The use of Flutter Rust Bridge simplifies the development process while maintaining the full power and flexibility of the Matrix SDK.

For production use, consider adding:
- Proper error handling and retry logic
- Unit and integration tests
- Security hardening
- Performance optimization
- Offline support
- Push notifications 