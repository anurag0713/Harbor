import XCTest
@testable import Harbor

final class SimulatorDeviceTests: XCTestCase {

    func testDecodingSimctlResponse() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "dataPath": "/Users/test/data",
                "dataPathSize": 1000,
                "logPath": "/Users/test/log",
                "udid": "A1B2C3D4-E5F6-7890-1234-567890ABCDEF",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                "state": "Booted",
                "name": "iPhone 16 Pro"
              },
              {
                "dataPath": "/Users/test/data2",
                "dataPathSize": 1000,
                "logPath": "/Users/test/log2",
                "udid": "12345678-ABCD-EF01-2345-6789ABCDEF01",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
                "state": "Shutdown",
                "name": "iPhone 16"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SimctlDeviceListResponse.self, from: json)
        guard let devices = decoded.devices["com.apple.CoreSimulator.SimRuntime.iOS-18-2"] else {
            XCTFail("Expected iOS 18-2 devices")
            return
        }

        XCTAssertEqual(devices.count, 2)

        let booted = devices[0]
        XCTAssertEqual(booted.name, "iPhone 16 Pro")
        XCTAssertTrue(booted.isBooted)
        XCTAssertEqual(booted.udid, "A1B2C3D4-E5F6-7890-1234-567890ABCDEF")

        let shutdown = devices[1]
        XCTAssertEqual(shutdown.name, "iPhone 16")
        XCTAssertFalse(shutdown.isBooted)
    }

    func testSimulatorShortVersion() {
        var device = SimulatorDevice(
            udid: "1234",
            name: "iPhone 16",
            state: "Booted",
            isAvailable: true
        )
        device.runtime = "iOS 18 2"
        XCTAssertEqual(device.shortVersion, "v18.2")
    }
}
