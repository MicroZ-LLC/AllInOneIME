#if os(Windows)
@testable import AllInOneIMEEngineKit
import Testing

/// `--render-panel`'s samples: the image they show is the checkout's, for a build only.
struct PanelSamplesTests {
    @Test func theSamplesImageIsTheCheckoutsOnly() {
        let build = #"C:\Users\me\repo\Windows\.build\x86_64-unknown-windows-msvc\debug\AllInOneIMEEngine.exe"#
        #expect(PanelSamples.checkoutIcon(executable: build, exists: { $0 == #"C:\Users\me\repo\Resources\AppIcon.png"# })
                == #"C:\Users\me\repo\Resources\AppIcon.png"#)
        // Never one further up (C:\Resources, which any user of the PC may make), nor for a copy that isn't a build.
        #expect(PanelSamples.checkoutIcon(executable: build, exists: { !$0.hasPrefix(#"C:\Users\me\repo\"#) }) == nil)
        #expect(PanelSamples.checkoutIcon(executable: #"C:\Program Files\AllInOneIME\0.6.5\AllInOneIMEEngine.exe"#,
                                          exists: { _ in true }) == nil)
        #expect(PanelSamples.checkoutIcon(executable: #"C:\.build\debug\AllInOneIMEEngine.exe"#, exists: { _ in true }) == nil)
    }
}
#endif
