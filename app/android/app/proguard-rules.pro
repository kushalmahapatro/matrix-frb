# Keep rustls-platform-verifier Android component (JNI-used by Rust TLS).
# ProGuard cannot see JNI usage, so these classes must be kept explicitly.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
