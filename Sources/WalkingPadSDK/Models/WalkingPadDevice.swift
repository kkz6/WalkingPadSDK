@preconcurrency import CoreBluetooth
import Foundation

public struct WalkingPadDevice: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let peripheral: CBPeripheral

    public init(peripheral: CBPeripheral) {
        self.id = peripheral.identifier
        self.name = peripheral.name ?? "Unknown WalkingPad"
        self.peripheral = peripheral
    }
}
