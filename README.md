# WalkingPadSDK

A Swift SDK for controlling KingSmith WalkingPad treadmills over Bluetooth Low Energy. Supports FTMS (Fitness Machine Service) and legacy F7/KingSmith proprietary protocols with automatic detection.

## Supported Devices

| Device | Protocol | Status |
|--------|----------|--------|
| KS-HD-Z1D | FTMS + KingSmith proprietary | Tested |
| WalkingPad A1/C1/C2 | Legacy F7 | Supported |
| Other KingSmith `KS-*` models | Auto-detected | Supported |

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kkz6/WalkingPadSDK.git", from: "1.0.0")
]
```

## Requirements

- macOS 14+ or watchOS 10+
- Swift 6.0+
- Bluetooth permission: add `NSBluetoothAlwaysUsageDescription` to your Info.plist

## Quick Start

```swift
import WalkingPadSDK

let controller = WalkingPadController()

// Observe status updates
controller.onStatusUpdate = { status in
    print("Speed: \(status.speedKmh) km/h, Time: \(status.formattedTime)")
}

// Scan for devices
controller.startScanning()

// Connect when a device is found
if let device = controller.discoveredDevices.first {
    controller.connect(to: device)
}

// Once connected, control the treadmill
await controller.startBelt()
await controller.setSpeed(30) // 3.0 km/h
await controller.stopBelt()

// Sleep/wake the device
controller.sleepDevice()
controller.wakeDevice()
```

## Architecture

```
WalkingPadController (public API)
    ├── WalkingPadScanner (BLE discovery)
    ├── WalkingPadConnection (connection lifecycle)
    │   └── WalkingPadPeripheral (service/characteristic management)
    └── Protocols (auto-detected)
        ├── FTMSProtocol (Bluetooth FTMS standard)
        ├── KingSmithProtocol (proprietary sleep/wake/init)
        └── WalkingPadParser (legacy F7 protocol)
```

### Key Types

- **`WalkingPadController`** — Main entry point. Handles scanning, connecting, and sending commands.
- **`WalkingPadDevice`** — A discovered BLE peripheral.
- **`TreadmillStatus`** — Live data: speed, distance, time, calories, belt state.
- **`ConnectionState`** — `.disconnected` / `.scanning` / `.connecting` / `.connected` / `.ready`
- **`DeviceProtocol`** — `.ftms` or `.legacy` (auto-detected after connection)

## BLE Protocol Details

### FTMS (Fitness Machine Service)

Standard Bluetooth protocol (service UUID `1826`). Used by newer KingSmith models.

| Characteristic | UUID | Purpose |
|---------------|------|---------|
| Treadmill Data | 2ACD | Speed, distance, calories, time (notifications) |
| Control Point | 2AD9 | Start, stop, set speed (write with response) |
| Machine Status | 2ADA | Events: stopped, started, speed changed |

Speed is in 0.01 km/h units. The SDK converts to tenths internally.

Control sequence: `RequestControl (0x00)` → `Start (0x07)` → `SetSpeed (0x02, lo, hi)` → `Stop (0x08, 0x01)`

### Legacy F7 Protocol

Used by older WalkingPad models (A1, C1, C2). Frame format: `F7 [cmd] [data...] [crc] FD`

Known service UUID sets: `FE00/FE01/FE02`, `FFF0/FFF1/FFF2`, `FFC0/FFC1/FFC2`

### KingSmith Proprietary

Custom service `24E2521C-F63B-48ED-85BE-C5330A00FDF7` for sleep/wake and device initialization. Works alongside FTMS on newer models.

## Testing

```bash
swift test
```

55 tests covering FTMS parsing, KingSmith command generation, legacy protocol, and model conversions.

## License

MIT
