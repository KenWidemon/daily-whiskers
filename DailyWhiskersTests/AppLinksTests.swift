import Foundation
import Testing
@testable import DailyWhiskers

@Suite("Public links")
struct AppLinksTests {
    @Test("Public destinations use the verified HTTPS site")
    func destinations() {
        for (url, path) in [
            (AppLinks.privacyPolicy, "/daily-whiskers-site/privacy/"),
            (AppLinks.support, "/daily-whiskers-site/support/")
        ] {
            #expect(url.scheme == "https")
            #expect(url.host == "kenwidemon.github.io")
            #expect(url.path == String(path.dropLast()))
            #expect(url.query == nil)
            #expect(url.fragment == nil)
        }
    }
}
