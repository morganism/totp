# 🔐 TOTP Authenticator — Apple Watch + iPhone

Native SwiftUI port of your PWA at `morganism/totp`.  
Runs fully offline. RFC 6238 compliant. Syncs accounts from iPhone → Watch via WatchConnectivity.

---

## 📁 File Structure

```
TOTPWatch/
├── Shared/                        ← Used by BOTH targets
│   ├── TOTPEngine.swift           ← RFC 6238/4226 TOTP engine (port of PWA JS)
│   ├── AccountStore.swift         ← Account model + persistence
│   └── WatchSessionManager.swift  ← iPhone ↔ Watch sync
│
├── WatchApp/                      ← watchOS target
│   ├── TOTPWatchApp.swift         ← App entry point
│   ├── WatchContentView.swift     ← Account list (scrollable)
│   ├── WatchCodeView.swift        ← Full-screen code + countdown ring
│   └── WatchAddAccountView.swift  ← Add account on Watch
│
└── iPhoneApp/                     ← iOS companion target
    ├── TOTPiPhoneApp.swift        ← App entry point
    ├── iPhoneContentView.swift    ← 2-column card grid (matches PWA layout)
    ├── iPhoneAddAccountView.swift ← Add: Manual / QR Scan / URI Import
    └── iPhoneExportView.swift     ← Export: JSON / Base64 / otpauth URIs
```

---

## 🛠 Xcode Setup (step by step)

### 1. Create the project

1. Open Xcode → **File > New > Project**
2. Choose **iOS App** (we'll add Watch later)
3. Settings:
   - **Product Name**: `TOTPAuthenticator`
   - **Bundle ID**: `com.yourname.totp`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - ✅ Include Tests: No

### 2. Add the watchOS target

1. **File > New > Target**
2. Choose **watchOS > App**
3. Settings:
   - **Product Name**: `TOTPWatch`
   - **Bundle ID**: `com.yourname.totp.watchkitapp`
   - ✅ When prompted "Activate scheme?" → **Activate**

### 3. Add all source files

**Option A — Drag & Drop (easiest)**

1. In Finder, open the `TOTPWatch/` folder from this zip
2. Drag `Shared/` into Xcode's Project Navigator under the root group
   - When prompted: ✅ **Add to targets**: check **both** `TOTPAuthenticator` AND `TOTPWatch`
3. Drag `iPhoneApp/` files → add to `TOTPAuthenticator` target only
4. Drag `WatchApp/` files → add to `TOTPWatch` target only

**Option B — File > Add Files to Project**

Repeat for each file, selecting the correct target membership in the right panel.

### 4. Configure capabilities

**iPhone target** (`TOTPAuthenticator`):
- Signing & Capabilities → + Capability → **WatchKit App** (if not auto-added)

**Watch target** (`TOTPWatch`):
- Signing & Capabilities → + Capability → **WatchKit App**

Both targets need the same **Team** selected in Signing.

### 5. Info.plist — Camera permission (iPhone only)

Add to `TOTPAuthenticator/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to scan TOTP QR codes</string>
```

### 6. Build & Run

- Select **TOTPAuthenticator** scheme → run on your iPhone
- Select **TOTPWatch** scheme → run on Apple Watch simulator or real watch

---

## 📱 Features

### iPhone App
| PWA Feature | Native Equivalent |
|---|---|
| Account grid with cards | 2-column SwiftUI grid |
| Countdown progress bar | Linear progress bar, animates |
| Click code to copy | Tap card → copies to clipboard |
| Add: Manual entry | `ManualEntryTab` form |
| Add: QR scan | `QRScanTab` with AVFoundation |
| Add: Import URI/JSON/Base64 | `URIImportTab` |
| Export: JSON/Base64/URI | `iPhoneExportView` with ShareSheet |
| Search bar | `.searchable()` modifier |
| Dark/Light/Auto theme | `@AppStorage` color scheme |

### Watch App
| Feature | Detail |
|---|---|
| Account list | Scrollable carousel with countdown rings |
| Full-screen code view | Tap to copy, haptic feedback |
| Countdown ring | Circular progress matches seconds remaining |
| Expiring code warning | Turns red at ≤5 seconds |
| Add on Watch | Manual entry or paste otpauth:// URI |
| Sync from iPhone | Automatic via WatchConnectivity |

---

## 🔒 Security Notes

- Secrets stored in **UserDefaults** (plain) — for production, migrate to **Keychain**
- No network access required — all TOTP generated on-device
- Import your existing accounts from the PWA using **Export → JSON** then **Import → JSON**

---

## 📲 Importing from your PWA

1. Open the PWA → click **📤** (export)
2. Choose **JSON** format → copy or download
3. Open the iPhone app → **+** → **Import URI** tab → paste JSON → **Import**
4. Accounts sync automatically to your Watch

---

## 🧪 Test Secret

Use this to verify the TOTP engine works correctly:

```
Secret:  JBSWY3DPEHPK3PXP
Issuer:  Test
Account: test@example.com
```

Cross-check the generated code with your PWA or another authenticator — they should match.
