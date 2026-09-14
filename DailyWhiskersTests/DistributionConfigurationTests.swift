import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Distribution configuration")
struct DistributionConfigurationTests {
    private func packagedInfo() throws -> [String: Any] {
        // Bundle.infoDictionary resolves device-specific keys for the running idiom.
        let url = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("iPad declares all orientations without requiring full screen")
    func iPadOrientations() throws {
        let info = try packagedInfo()
        let orientations = try #require(info["UISupportedInterfaceOrientations~ipad"] as? [String])
        #expect(Set(orientations) == Set([
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight"
        ]))
        #expect(info["UIRequiresFullScreen"] as? Bool != true)
    }

    @Test("App declares exempt encryption in its packaged metadata")
    func exemptEncryptionDeclaration() throws {
        let info = try packagedInfo()
        let value = try #require(info["ITSAppUsesNonExemptEncryption"] as? NSNumber)
        #expect(CFGetTypeID(value) == CFBooleanGetTypeID())
        #expect(value.boolValue == false)
    }

    @Test("iPhone keeps portrait and both landscape orientations")
    func iPhoneOrientations() throws {
        let info = try packagedInfo()
        let orientations = try #require(info["UISupportedInterfaceOrientations~iphone"] as? [String])
        #expect(Set(orientations) == Set([
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight"
        ]))
    }
}
