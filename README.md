# NoxRail

**Secure, Offline BLE Mesh Messaging for iOS**

NoxRail is a production-ready iOS application that enables secure peer-to-peer messaging without internet connectivity using Bluetooth Low Energy (BLE). Messages are encrypted end-to-end and can traverse multiple devices through a mesh network.

## Features

- 🔒 **End-to-End Encryption** - All messages encrypted using ECDH + AES-GCM
- 📡 **BLE Mesh Network** - Works completely offline using Bluetooth
- 🔄 **Multi-Hop Routing** - Messages can traverse through relay nodes
- 💬 **Direct & Group Chat** - Support for 1-to-1 and group conversations
- 🎨 **Modern UI** - Beautiful SwiftUI interface with dark mode support
- 💾 **Persistent Storage** - Messages survive app restarts

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Real iOS device (BLE simulation is limited)

## Quick Start

### 1. Generate Xcode Project

```bash
cd /Users/upwansingh/Desktop/NoxRail
xcodegen generate
```

### 2. Build the Project

```bash
# Build for device
xcodebuild -project NoxRail.xcodeproj \
    -scheme NoxRail \
    -destination 'generic/platform=iOS' \
    -configuration Debug \
    build

# Or open in Xcode
open NoxRail.xcodeproj
```

### 3. Deploy to Device

1. Open `NoxRail.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Connect your iOS device
4. Build and run (⌘R)

## Architecture

```
NoxRail/
├── Models/              # Data models (Message, Chat, Peer, etc.)
├── Services/
│   ├── BLE/            # Bluetooth Central & Peripheral managers
│   ├── MeshRouting/    # Multi-hop routing engine
│   ├── Encryption/     # ECDH + AES-GCM encryption
│   └── Persistence/    # SwiftData storage
├── ViewModels/         # MVVM view models
├── Views/              # SwiftUI views
│   └── Components/     # Reusable UI components
└── Utilities/          # Extensions and helpers
```

## Mesh Routing Design

### How It Works

1. **Discovery**: Devices scan for nearby NoxRail peers via BLE advertising
2. **Connection**: When peers connect, they automatically exchange public keys
3. **Message Routing**: Messages are encrypted and broadcast to connected peers
4. **Relaying**: If relay mode is enabled, devices forward messages for others
5. **Delivery**: The destination device decrypts and displays the message

### Packet Structure

```swift
struct RoutingPacket {
    let packetId: String        // Unique identifier
    let type: PacketType        // message, keyExchange, ack, etc.
    let sourcePeerId: String    // Original sender
    let destinationId: String   // Target recipient
    var hopCount: Int           // Incremented at each relay
    let maxHops: Int            // TTL (default: 5)
    let payload: Data           // Encrypted content
}
```

### Loop Prevention

- Each device maintains a `seenMessages` cache
- Duplicate packets are immediately dropped
- Cache entries expire after 5 minutes
- Hop count prevents infinite forwarding

### Relay Mode

When enabled:
- Device forwards messages intended for other recipients
- Only encrypted ciphertext is relayed (no decryption)
- Increases battery usage but extends network range

## Encryption Model

### Key Generation

- P-256 ECDH keypair generated on first launch
- Private key stored securely in iOS Keychain
- Public key exchanged with peers during connection

### Key Exchange

```
Alice                        Bob
  |                           |
  |-- Public Key Exchange --->|
  |<-- Public Key Exchange ---|
  |                           |
  |   (ECDH Shared Secret)    |
  |                           |
```

### Message Encryption

1. **ECDH Key Agreement**: Derive shared secret from sender's private key + recipient's public key
2. **HKDF Key Derivation**: Derive symmetric key using SHA-256
3. **AES-GCM Encryption**: Encrypt message with random nonce
4. **Transmit**: Send nonce + ciphertext + auth tag + sender's public key

### Security Properties

- **Confidentiality**: Only sender and recipient can read messages
- **Integrity**: GCM authentication tag detects tampering
- **Replay Protection**: Message IDs prevent replay attacks
- **Forward Secrecy**: Not implemented (would require session keys)

## iOS Constraints

### Foreground Only

**Important**: BLE mesh routing only works while the app is in the foreground. iOS severely limits background Bluetooth activity, making reliable background relaying impractical.

### Why This Matters

- Active scanning/advertising stops when backgrounded
- Connected peripherals may be disconnected
- Notifications cannot be guaranteed for incoming messages

### Recommendation

Keep NoxRail in the foreground when actively messaging or relaying for others.

## Battery Considerations

NoxRail uses significant battery when active:

- Continuous BLE scanning
- Peripheral advertising
- Data processing for routing

**Tips to reduce battery usage:**
- Disable relay mode when not needed
- Close the app when not messaging

## Testing

### Multi-Device Testing

1. Install NoxRail on 3+ iOS devices
2. Launch the app on all devices
3. Devices should discover each other in "Nearby" tab
4. Connect and exchange keys
5. Start chatting!

### Testing Multi-Hop

1. Set up Device A, B, and C in a line (A can see B, B can see C, but A cannot see C)
2. Enable relay mode on Device B
3. Send a message from A to C
4. Message should arrive "via 1 hop"

## Known Limitations

1. **Foreground Only** - No background mesh routing
2. **Range Limited** - BLE range is ~10-30m depending on environment
3. **No Guaranteed Delivery** - Best effort routing
4. **Single Device Identity** - No multi-device sync
5. **No Offline Key Exchange** - Both devices must be online simultaneously
6. **No Perfect Forward Secrecy** - Compromised keys can decrypt past messages

## Troubleshooting

### "No Nearby Devices"

- Ensure Bluetooth is enabled on all devices
- Check that NoxRail has Bluetooth permission
- Try moving devices closer together
- Restart the app

### "Key Exchange Required"

- Tap on the peer in Nearby devices
- Tap "Exchange Keys" button
- Wait for confirmation

### Messages Not Sending

- Verify you're connected to the recipient
- Check that keys have been exchanged
- Ensure the recipient's app is in foreground

## License

This project is provided as-is for educational purposes.

## Acknowledgments

Built with:
- SwiftUI
- CoreBluetooth
- CryptoKit
- SwiftData
