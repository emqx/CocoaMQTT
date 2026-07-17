import Foundation
import XCTest
@testable import CocoaMQTT

final class PrivacyManifestTests: XCTestCase {

    #if IS_SWIFT_PACKAGE
    func testSwiftPackageIncludesPrivacyManifest() {
        XCTAssertNotNil(CocoaMQTTResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }
    #endif
}
