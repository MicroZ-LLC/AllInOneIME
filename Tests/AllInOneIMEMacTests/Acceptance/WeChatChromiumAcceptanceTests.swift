import AllInOneIMETestSupport
import AllInOneIMEMac
import Foundation
import Testing

// Issues #193 and #197: in WeChat for macOS (com.tencent.xinWeChat) the first pinyin letter stays in the field
// ("c测试"). The cause suspected: the input method doesn't tell WeChat as a Chromium app (`ChromiumApps.hasChromium`),
// so it doesn't keep from the field the keys Chromium apps act on. WeChat's Contents/Frameworks carries Chromium's
// parts under names of its own: ANGLE's libEGL.dylib and libGLESv2.dylib, Mojo (libmmmojo.dylib), Cronet
// (mmcronet.framework); none of them is Electron's or a browser's framework, and none has Chromium or CEF in its name.
// Expected: a bundle with exactly those frameworks is told as a Chromium app's, by its bundle and by its bundle id; a
// native app's bundle with only WeChat's own frameworks and libraries (none of Chromium's) is still not one.
struct WeChatChromiumAcceptanceTests {
    /// What WeChat's Contents/Frameworks holds, as reported for the issues.
    static let weChatFrameworks = [
        "andromeda.framework", "ConfSDKdyn.framework", "ilink2.framework", "libEGL.dylib", "libGLESv2.dylib",
        "libmmmojo.dylib", "libwxocr.dylib", "mmcronet.framework", "MultiMediaDyn.framework", "owl.framework",
        "ProtobufLite.framework", "wechat.dylib",
    ]

    /// A bundle in a temporary folder with `frameworks` in its Contents/Frameworks.
    static func bundle(_ name: String, _ frameworks: [String], in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent(name + ".app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        for framework in frameworks {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Frameworks/" + framework),
                                                    withIntermediateDirectories: true)
        }
        return app
    }

    static func folder() throws -> URL {
        let folder = TestScratch.temporary("wechat-chromium-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// WeChat's frameworks make its bundle a Chromium app's: told by the bundle, and by WeChat's bundle id where
    /// `locate` finds that bundle.
    @Test func weChatsFrameworksAreToldAsAChromiumApp() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let weChat = try Self.bundle("WeChat", Self.weChatFrameworks, in: folder)
        #expect(ChromiumApps.hasChromium(bundle: weChat),
                "a bundle with WeChat's frameworks (\(Self.weChatFrameworks)) isn't told as a Chromium app")
        let known = ChromiumApps.Known(now: { 100 }) { $0 == "com.tencent.xinWeChat" ? weChat : nil }
        #expect(known.isChromium("com.tencent.xinWeChat"), "WeChat, by its bundle id, isn't told as a Chromium app")
    }

    /// Only WeChat's own frameworks and libraries, none of Chromium's: a native app's bundle, not one.
    @Test func aNativeBundleWithOnlyWeChatsOwnFrameworksIsNot() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let native = ["ProtobufLite.framework", "MultiMediaDyn.framework", "libwxocr.dylib", "wechat.dylib", "ilink2.framework"]
        #expect(!ChromiumApps.hasChromium(bundle: try Self.bundle("Native", native, in: folder)),
                "a bundle with only \(native) is told as a Chromium app")
    }
}
