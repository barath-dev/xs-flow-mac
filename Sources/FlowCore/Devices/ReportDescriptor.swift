import Foundation

/// Minimal HID report descriptor walker: just enough to find which report IDs
/// carry Feature items, so we can pick the Elan config interface.
public enum ReportDescriptor {
    public static func featureReportIDs(in descriptor: Data) -> Set<Int> {
        let bytes = [UInt8](descriptor)
        var ids: Set<Int> = []
        var currentID = 0
        var i = 0
        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE { // long item: 0xFE, size, tag, data...
                guard i + 1 < bytes.count else { break }
                i += 3 + Int(bytes[i + 1])
                continue
            }
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            let tagAndType = prefix & 0xFC
            var value = 0
            for n in 0..<size where i + 1 + n < bytes.count {
                value |= Int(bytes[i + 1 + n]) << (8 * n)
            }
            switch tagAndType {
            case 0x84: currentID = value          // Global: Report ID
            case 0xB0: ids.insert(currentID)      // Main: Feature
            default: break
            }
            i += 1 + size
        }
        return ids
    }
}
