# Recovery Phrase Encoding/Decoding Flow

## Current Implementation (NO Ku Encryption)

### During Bootstrap (Encoding):
**Location:** `e2e_service.dart` line 245
```dart
final recoveryPhraseEncoded = base64Encode(utf8.encode(recoveryPhrase));
```

**Method:**
1. UTF-8 encode the recovery phrase string → bytes
2. Base64 encode the bytes → base64 string
3. **NO encryption with Ku** - just encoding

**What's sent to backend:**
- `recoveryPhrases`: Plain text recovery phrase
- `recoveryPhraseEncoded`: Base64 encoded recovery phrase (still plain text, just encoded)

### When Getting Recovery Phrase (Decoding):
**Location:** `e2e_service.dart` line 1909-1910
```dart
final decodedBytes = base64Decode(recoveryPhraseEncoded);
final recoveryPhrase = utf8.decode(decodedBytes);
```

**Method:**
1. Base64 decode the string → bytes
2. UTF-8 decode the bytes → recovery phrase string
3. **NO decryption with Ku** - just decoding

## Summary:
- **Encoding**: UTF-8 → Base64 (NO Ku encryption)
- **Decoding**: Base64 → UTF-8 (NO Ku decryption)
- **Security**: Recovery phrase is sent/stored in plain text (just base64 encoded)

## If you want to encrypt with Ku:
We would need to:
1. Encrypt recovery phrase with Ku using AES-GCM during bootstrap
2. Decrypt recovery phrase with Ku using AES-GCM when retrieving
3. Backend would store encrypted phrase, frontend decrypts with Ku

