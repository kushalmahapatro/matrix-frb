# Android Keystore Configuration

This project uses a custom keystore for signing all Android builds (debug, profile, and release) to prevent APK uninstallation when switching between build modes.

## Files

- `keystore.properties` - Contains keystore credentials (DO NOT commit to git)
- `matrix-keystore.jks` - The actual keystore file (DO NOT commit to git)
- `proguard-rules.pro` - ProGuard rules for release builds

## Keystore Details

- **Keystore file**: `matrix-keystore.jks`
- **Key alias**: `matrix_key`
- **Store password**: `password`
- **Key password**: `password`
- **Validity**: 10,000 days
- **Key algorithm**: RSA 2048-bit

## Security Notes

⚠️ **IMPORTANT**: 
- The keystore file and properties file are already added to `.gitignore`
- Never commit these files to version control
- Keep a secure backup of the keystore file
- The passwords used here are for development only - use stronger passwords for production

## Usage

The keystore is automatically used for all build types:
- `flutter run` (debug)
- `flutter run --profile` (profile) 
- `flutter run --release` (release)
- `flutter build apk` (release)

## Regenerating the Keystore

If you need to regenerate the keystore:

```bash
cd android
keytool -genkey -v -keystore matrix-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias matrix_key \
  -storepass matrix123456 \
  -keypass password \
  -dname "CN=Matrix App, OU=Development, O=Matrix, L=City, S=State, C=US"
```

## Troubleshooting

If you get signing errors:
1. Ensure `keystore.properties` exists and has correct values
2. Verify `matrix-keystore.jks` exists in the android directory
3. Check that passwords match between properties file and keystore
4. Clean and rebuild: `flutter clean && flutter pub get`

