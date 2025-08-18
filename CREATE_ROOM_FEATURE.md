# Create Room Feature

This document describes the create room functionality implemented in the Matrix Flutter client.

## Overview

The create room feature allows users to create two types of rooms:
1. **Direct Chat** - 1-on-1 private conversations
2. **Group Chat** - Multi-participant group conversations

## Features

### Direct Chat Creation
- Search for users by username or Matrix ID
- Select a single user to create a direct message room
- Automatically sets up a private, encrypted room between two users

### Group Chat Creation
- Create named group rooms
- Search and add multiple participants
- Set a custom group name
- Create private group rooms with invited participants

### User Search
- Search users by partial username or full Matrix ID
- Support for both `@username:homeserver` format and simple `username` format
- Real-time search results as you type

## User Interface

### Room Type Selection
- Toggle between "Direct Chat" and "Group Chat" modes
- Visual indicators show the selected mode
- Different UI elements appear based on the selected type

### User Search and Selection
- Search field with placeholder text guidance
- Real-time search results display
- Add/remove participants with visual feedback
- Selected participants list with removal option

### Create Button
- Context-aware button text ("CREATE DIRECT CHAT" vs "CREATE GROUP CHAT")
- Loading state during room creation
- Success/error feedback via snackbars

## Technical Implementation

### Rust Backend Functions

#### `search_users(query: String) -> Result<Vec<UserSearchResult>, String>`
- Searches for users based on the query
- Returns user ID, display name, and avatar URL
- Currently implements basic search logic (can be enhanced with homeserver directory search)

#### `create_direct_room(user_id: String) -> Result<String, String>`
- Creates a direct message room with the specified user
- Sets `is_direct: true` and uses `TrustedPrivateChat` preset
- Returns the created room ID

#### `create_group_room(name: String, user_ids: Vec<String>) -> Result<String, String>`
- Creates a group room with the specified name and participants
- Sets `is_direct: false` and uses `PrivateChat` preset
- Invites all specified users to the room
- Returns the created room ID

### Flutter Frontend

#### CreateRoomScreen Widget
- Stateful widget managing room creation flow
- Handles user search, selection, and room creation
- Provides responsive UI with proper error handling

#### Integration with Chat Listing
- Floating action button opens create room screen
- Refreshes room list after successful room creation
- Smooth page transitions with fade animations

## Usage Flow

1. **Access**: Tap the "+" floating action button in the chat listing screen
2. **Select Type**: Choose between "Direct Chat" or "Group Chat"
3. **Name Group** (Group Chat only): Enter a name for the group
4. **Search Users**: Type username or Matrix ID to search for participants
5. **Add Participants**: Tap the "+" button next to search results to add users
6. **Review Selection**: See selected participants in the list below
7. **Create Room**: Tap the create button to create the room
8. **Navigate**: Automatically returns to chat listing with the new room visible

## Error Handling

- **Search Errors**: Display error messages for failed user searches
- **Creation Errors**: Show detailed error messages for room creation failures
- **Validation**: Prevent creation without participants or group name (when required)
- **Loading States**: Visual feedback during async operations

## Future Enhancements

- **Enhanced User Search**: Integration with homeserver user directory
- **User Profiles**: Display user avatars and profile information
- **Room Settings**: Advanced room configuration options
- **Bulk User Import**: Import users from contacts or CSV
- **Room Templates**: Pre-configured room types and settings
- **Invitation Management**: Handle invitation responses and retries

## Testing

Basic widget tests are included to verify:
- UI element rendering
- Room type switching
- Search functionality
- User selection flow

Run tests with:
```bash
flutter test test/create_room_screen_test.dart
```

## Dependencies

- **Flutter Rust Bridge**: For Rust-Dart interop
- **Matrix SDK**: For Matrix protocol operations
- **Provider**: For state management
- **Material Design**: For UI components

## Files Modified/Created

### New Files
- `lib/src/create_room_screen.dart` - Main create room UI
- `test/create_room_screen_test.dart` - Widget tests
- `CREATE_ROOM_FEATURE.md` - This documentation

### Modified Files
- `rust/src/matrix/rooms.rs` - Added room creation and user search functions
- `lib/src/chat_listing.dart` - Added navigation to create room screen
- Generated Flutter Rust Bridge bindings updated automatically

## Matrix Protocol Details

The implementation follows Matrix specification for:
- Room creation with proper presets (`TrustedPrivateChat` for DMs, `PrivateChat` for groups)
- User invitations to rooms
- Direct message room marking (`is_direct: true`)
- Room naming and metadata

This creates fully compliant Matrix rooms that work with any Matrix client.