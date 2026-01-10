# Login Flow Implementation - Device Keypair Management

## GLOBAL RULE (ALWAYS EXECUTE ON LOGIN)

✅ **Implemented**: On every login attempt:
- Check if local keypair exists → use it
- If missing → generate new keypair and store it securely
- Always send the public key to the backend with the login request

## Implementation Details

### 1. Device Keypair Management (`e2e_service.dart`)
- **New Method**: `ensureDeviceKeypairExists()`
  - Checks if SKd exists in secure storage
  - If exists: derives public key (PKd) from existing SKd
  - If missing: generates new P-256 keypair, stores SKd securely, returns PKd
  - Always returns public key in base64 format

### 2. Login Request (`auth_service.dart`, `login_screen.dart`)
- **Updated**: Always includes `device_public_key` in login request
- **Updated**: `_deriveDevicePublicKey()` in both `AuthRepository` and `LoginScreen` now calls `ensureDeviceKeypairExists()`

### 3. Backend Response Model (`login_response_model.dart`)
- **New Fields**:
  - `isNewUser` (bool?)
  - `isDeviceFound` (bool?)
  - `isDeviceLinkedWithUser` (bool?)
  - `isPublicKeyMatched` (bool?)
- **Parser**: Handles bool, string, and int types from backend

### 4. Decision Logic (`auth_repository.dart`)
- **Simplified Logic**:
  1. If `is_device_found = false`:
     - If `is_new_user = true` → Proceed to normal login/registration
     - If `is_new_user = false` → Go to QR pairing screen
  2. If `is_device_found = true`:
     - If `is_device_linked_with_user = false` → Show error: "This device belongs to another user. Access denied."
     - If `is_device_linked_with_user = true`:
       - If `is_public_key_matched = true` → Direct login
       - If `is_public_key_matched = false` → Go to pairing screen

## Files Modified

1. `lib/core/services/e2e_service.dart` - Added `ensureDeviceKeypairExists()`
2. `lib/data/repositories/auth_repository.dart` - Updated `_deriveDevicePublicKey()` and decision logic
3. `lib/data/services/auth_service.dart` - Updated to always send device_public_key
4. `lib/data/models/login_response_model.dart` - Added new backend response fields
5. `lib/screens/login/login_screen.dart` - Updated `_deriveDevicePublicKey()` to use new method

## Flow Diagram

```
Login Attempt
    ↓
ensureDeviceKeypairExists()
    ↓
[Keypair exists?]
    ├─ Yes → Derive PKd from SKd
    └─ No → Generate new keypair, store SKd, extract PKd
    ↓
Send login request with device_public_key
    ↓
Backend Response:
    - is_new_user
    - is_device_found
    - is_device_linked_with_user
    - is_public_key_matched
    ↓
Decision Logic (see above)
    ↓
Navigate to appropriate screen
```

