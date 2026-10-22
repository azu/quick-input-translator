import Foundation
import Testing
@testable import QuickTranslateInput

@MainActor struct AppUpdaterTests {
    private var releaseInfo: [String: Any] {
        ["QTIReleaseChannel": "signed-release",
         "SUFeedURL": "https://github.com/azu/quick-input-translator/releases/latest/download/appcast.xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
    }

    @Test func localAndUnconfiguredBuildsNeverStartReleaseUpdates() {
        #expect(!AppUpdater.isConfigured([:]))
        var info = releaseInfo
        info.removeValue(forKey: "QTIReleaseChannel")
        #expect(!AppUpdater.isConfigured(info))
        info["QTIReleaseChannel"] = "development"
        #expect(!AppUpdater.isConfigured(info))
    }

    @Test func releaseRequiresHTTPSAndARealPublicKey() {
        #expect(AppUpdater.isConfigured(releaseInfo))
        var info = releaseInfo
        info["SUFeedURL"] = "http://github.com/feed.xml"
        #expect(!AppUpdater.isConfigured(info))
        info["SUFeedURL"] = "https:feed.xml"
        #expect(!AppUpdater.isConfigured(info))
        info = releaseInfo
        for key in ["", "placeholder", Data(repeating: 1, count: 31).base64EncodedString()] {
            info["SUPublicEDKey"] = key
            #expect(!AppUpdater.isConfigured(info))
        }
    }
}
