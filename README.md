# Matrix Terminal Client

A Matrix protocol client built with Flutter and Rust, featuring a terminal-inspired UI reminiscent of the Matrix movie aesthetic.

## Features

- **Matrix Movie Aesthetic**: Terminal-style UI with green-on-black color scheme and JetBrains Mono font
- **Elementary State Management**: Clean architecture using Elementary pattern
- **Feature-First Structure**: Organized by features rather than layers
- **Cross-Platform**: Runs on iOS, Android, macOS, Linux, Windows, and Web
- **Real-time Messaging**: Matrix protocol integration via Rust SDK
- **Terminal Animations**: Matrix rain effect and smooth transitions

## Architecture

### Feature-First Structure

```
lib/src/
├── core/                    # Shared components and utilities
│   ├── presentation/
│   │   ├── widgets/        # Reusable terminal UI components
│   │   └── theme/          # Matrix theme configuration
│   ├── domain/
│   │   └── services/       # Core services
│   └── utils/              # Utilities and helpers
├── features/
│   ├── auth/               # Authentication feature
│   │   ├── domain/
│   │   │   ├── models/     # Auth state models
│   │   │   └── services/   # Auth service`
│   │   └── presentation/
│   │       └── screens/    # Login, splash screens
│   ├── chat/               # Chat listing feature
│   │   ├── domain/
│   │   │   ├── models/     # Chat state models
│   │   │   └── services/   # Chat services
│   │   └── presentation/
│   │       └── screens/    # Chat listing screen
│   ├── rooms/              # Room/Timeline feature
│   │   ├── domain/
│   │   │   ├── models/     # Room and message models
│   │   │   └── services/   # Room services
│   │   └── presentation/
│   │       └── screens/    # Room timeline screen
│   └── settings/           # Settings feature
│       └── presentation/
│           └── screens/    # Settings screen
```

### State Management

Uses **Elementary** pattern for clean separation of concerns:
- **Widget**: Pure UI components
- **WidgetModel**: Business logic and state management
- **Model**: Data layer and external service calls

### Terminal UI Components

- `TerminalScreen`: Base screen with Matrix aesthetic
- `TerminalContainer`: Bordered containers with glow effects
- `TerminalButton`: Matrix-styled buttons
- `TerminalTextField`: Terminal-style input fields
- `TerminalStatusMessage`: Status messages with icons

## Matrix Movie Aesthetic

### Color Palette
- **Matrix Green**: `#00FF41` - Primary terminal green
- **Matrix Dark Green**: `#008F11` - Darker variant
- **Matrix Light Green**: `#65FF65` - Lighter variant
- **Matrix Accent**: `#00D4AA` - Accent color for highlights
- **Terminal Black**: `#000000` - Pure black background
- **Terminal Background**: `#0D1117` - Slightly lighter background

### Typography
- **Font**: JetBrains Mono (monospace)
- **Letter Spacing**: Increased for terminal feel
- **Glow Effects**: Text shadows for authentic CRT monitor look

### Animations
- **Matrix Rain**: Falling character animation on splash screen
- **Fade Transitions**: Smooth screen transitions
- **Glow Effects**: Subtle glowing borders and text

## Getting Started

### Prerequisites
- Flutter SDK (^3.7.2)
- Rust toolchain
- Matrix homeserver access

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate code:
   ```bash
   dart run build_runner build
   ```

4. Run the app:
   ```bash
   flutter run
   ```

### Development Commands

```bash
# Install dependencies
flutter pub get

# Generate freezed classes
dart run build_runner build

# Watch for changes
dart run build_runner watch

# Run tests
flutter test

# Build for release
flutter build apk          # Android
flutter build ios          # iOS
flutter build macos        # macOS
flutter build linux        # Linux
flutter build windows      # Windows
flutter build web          # Web
```

## Key Dependencies

- **elementary**: ^3.2.1 - State management
- **elementary_helper**: ^1.0.3 - Elementary utilities
- **freezed**: ^3.1.0 - Immutable data classes
- **flutter_rust_bridge**: 2.11.1 - Rust-Dart interop
- **auto_route**: ^8.4.0 - Navigation (planned)

## Matrix Integration

The app integrates with Matrix protocol via Rust SDK:
- Authentication (login/register)
- Room management
- Real-time messaging
- Session persistence

## Contributing

1. Follow the feature-first architecture
2. Use Elementary pattern for new screens
3. Maintain Matrix movie aesthetic
4. Add terminal-style animations where appropriate
5. Write tests for business logic

## License

This project is open source and available under the MIT License.