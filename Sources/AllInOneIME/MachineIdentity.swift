import AllInOneIMECore
import Foundation
import IOKit

/// This Mac's hardware, for sync through iCloud (`ICloudSyncEngine.machineID`): the core hashes the platform UUID
/// (`ICloudSync.machineID(platformUUID:)`), never keeping the UUID itself; reading it is the Mac's own (IOKit).
enum MachineIdentity {
    /// The sync record's machine id, nil when the platform UUID can't be read.
    static func syncID() -> String? { platformUUID().map(ICloudSync.machineID(platformUUID:)) }

    /// IOPlatformUUID from the I/O Registry.
    static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
