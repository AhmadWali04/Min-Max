import XCTest
@testable import MinMaxCore

final class MinMaxCoreTests: XCTestCase {
    func testPackageIdentity() {
        XCTAssertEqual(MinMaxCore.packageName, "MinMax")
        XCTAssertEqual(MinMaxCore.version, "0.1.0")
    }
}
