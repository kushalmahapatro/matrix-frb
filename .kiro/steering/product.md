# Matrix Flutter Client

A cross-platform Matrix protocol client built with Flutter and Rust, showcasing modern Matrix SDK integration using Flutter Rust Bridge.

## Product Vision
Demonstrate how to build a production-ready Matrix client using Flutter for UI and Rust for Matrix protocol handling, with seamless interop via Flutter Rust Bridge instead of traditional UniFFI bindings.

## Key Features
- **Authentication**: Login/registration with Matrix homeservers
- **Real-time Messaging**: Send/receive messages with live sync
- **Room Management**: Join rooms, view timelines, manage conversations
- **Cross-platform**: Native apps for iOS, Android, macOS, Linux, Windows, and Web
- **Matrix Aesthetic**: Terminal-inspired green-on-black theme with JetBrains Mono font
- **Session Persistence**: Secure local storage of authentication sessions

## Target Users
- Developers learning Matrix SDK integration
- Teams needing a customizable Matrix client
- Privacy-focused users wanting an open-source messaging solution

## Technical Differentiators
- Uses Flutter Rust Bridge for better type safety and performance vs UniFFI
- Direct Matrix SDK integration without FFI overhead
- Modern async/await patterns throughout
- Comprehensive logging and debugging support