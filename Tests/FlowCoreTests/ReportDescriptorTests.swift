import Foundation
import Testing
@testable import FlowCore

@Suite struct ReportDescriptorTests {
    @Test func bluetoothDescriptorHasNoFeatureReports() {
        // Captured from `ioreg` for "XS Flow S1" over BLE.
        let hex = "05010902a10185010901a100050919012908150025019508750181020501093009311601f826ff07750c9502810609381581257f750895018106050c0a38028106c0c0050c0901a1018503150026ff0319002aff03751095018100c0"
        let data = Data(stride(from: 0, to: hex.count, by: 2).map {
            UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16)!
        })
        #expect(ReportDescriptor.featureReportIDs(in: data).isEmpty)
    }

    @Test func findsFeatureReportID() {
        // Vendor page, report ID 6, 30-byte feature.
        let data = Data([0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x85, 0x06, 0x75, 0x08, 0x95, 0x1E, 0x09, 0x01, 0xB1, 0x02, 0xC0])
        #expect(ReportDescriptor.featureReportIDs(in: data) == [6])
    }
}
