import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMERime

/// Deployments as the app makes them log no error, which Troubleshoot would report from librime's logs ("Rime dictionary
/// failed to load", "Rime deployment failed"): on a fresh install and on an update from 0.7.2.1 (whose data had full
/// pinyin's schema alone, without Zhuyin's data linked into the pack), with full pinyin, a Shuangpin scheme and Zhuyin;
/// and while the settings change as librime deploys (fuzzy pinyin toggled, another way of typing picked: Settings, iCloud
/// sync), where the patch writer used to remove the compiled schema under the deployment, whose dictionary then failed to
/// compile ("error loading prism definition from …/build/rime_ice.schema.yaml"). Nor does a deployment warn that a file
/// it compiled before is missing (what that removal made it say). Each run in a process of its own (`RimeWorker`).
struct DeploymentLogTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-deployment-log-\(UUID().uuidString)")

    @Test(.enabled(if: ZhuyinSchemaTests.runs, "needs rime-ice, the Zhuyin data and OpenCC's data (make deps)"),
          arguments: [PinyinScheme.full, .xiaohe, .zhuyin])
    func aFreshInstallDeploysWithoutErrors(_ scheme: PinyinScheme) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("deployment-launch-\(scheme.rawValue)", root: root)
    }

    @Test(.enabled(if: ZhuyinSchemaTests.runs, "needs rime-ice, the Zhuyin data and OpenCC's data (make deps)"),
          arguments: [PinyinScheme.full, .xiaohe, .zhuyin])
    func anUpdateFrom0721DeploysWithoutErrors(_ scheme: PinyinScheme) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("deployment-0721", root: root)
        try RimeWorker.run("deployment-launch-\(scheme.rawValue)", root: root)
    }

    @Test(.enabled(if: ZhuyinSchemaTests.runs, "needs rime-ice, the Zhuyin data and OpenCC's data (make deps)"))
    func settingsChangedWhileDeployingLogNoErrors() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try RimeWorker.run("deployment-changes", root: root)
    }

    static let scenarios: [String: @Sendable (URL) throws -> Void] = {
        var scenarios: [String: @Sendable (URL) throws -> Void] = [
            // 0.7.2.1's data: its pack without Zhuyin's data, full pinyin's patch, the pack's schema list, deployed.
            "deployment-0721": { root in
                let app = try App(root, zhuyinLinked: false)
                try app.launch(.full, logs: "logs-0721")
                try app.checkLogs("logs-0721")
                #expect(app.compiled.contains("rime_ice.schema.yaml") && !app.compiled.contains("bopomofo.schema.yaml"))
            },
            // Settings changed as librime deploys: Zhuyin picked (its dictionaries compiled, a few seconds), fuzzy pinyin
            // toggled again and again meanwhile, each deployed again; then Xiaohe and n ↔ l, which the last deployment has.
            "deployment-changes": { root in
                let app = try App(root)
                try app.launch(.full, logs: "logs")
                let service = RimeService.shared
                app.compiledBefore = app.compiled
                app.settle(.zhuyin, fuzzy: [])
                var toggles = 0
                let deadline = Date().addingTimeInterval(20)
                while service.api.pointee.is_maintenance_mode() != 0 && Date() < deadline || toggles == 0 {
                    app.settle(.zhuyin, fuzzy: toggles % 2 == 0 ? ["z-zh"] : [])
                    toggles += 1
                    Thread.sleep(forTimeInterval: 0.02)
                }
                app.settle(.xiaohe, fuzzy: ["n-l"])
                try #require(service.waitUntilReady(timeout: 180))
                #expect(service.deploymentStatus == .succeeded)
                try app.checkLogs("logs")
                let session = try #require(service.makeSession())
                #expect(session.selectSchema(PinyinScheme.xiaohe.schema))
                #expect(session.selectSchema(PinyinScheme.fullSchema))
                for byte in "lan".utf8 { _ = session.processKey(Int32(byte), mask: 0) }
                let words = session.snapshot().candidates.map(\.text)
                #expect(words.contains { ["难", "南", "男"].contains($0) }, "lan with n ↔ l: \(words)")
            },
        ]
        // The app's launch (`RimeStartup.start`) with each way of typing, on the folder as it is: none (a fresh install) or
        // 0.7.2.1's.
        for scheme in [PinyinScheme.full, .xiaohe, .zhuyin] {
            scenarios["deployment-launch-\(scheme.rawValue)"] = { root in
                let app = try App(root)
                try app.launch(scheme, logs: "logs-launch")
                try app.checkLogs("logs-launch")
                let session = try #require(RimeService.shared.makeSession())
                #expect(session.selectSchema(scheme.schema))
            }
        }
        return scenarios
    }()

    /// The app's Rime as `RimeStartup` sets it up in `root`: the Chinese pack (rime-ice's data, linked; its schema list a
    /// file of its own, as the downloaded pack's is), the app's Lua and Zhuyin's data linked into it, the user folder.
    final class App: @unchecked Sendable {
        let pack: URL
        let user: URL
        let root: URL
        /// What the user folder's `build/` had compiled before the deployments `checkLogs` looks at.
        var compiledBefore: Set<String> = []

        init(_ root: URL, zhuyinLinked: Bool = true) throws {
            let fm = FileManager.default
            self.root = root
            user = root.appendingPathComponent("Rime")
            let store = LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks"))
            if fm.fileExists(atPath: store.folder(.chinesePinyin).path) {
                pack = store.folder(.chinesePinyin)
            } else {
                pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua",
                                                                 script: String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8))
                let list = pack.appendingPathComponent("default.custom.yaml")
                try fm.removeItem(at: list)
                try fm.copyItem(at: RimeFixture.sharedData.appendingPathComponent("default.custom.yaml"), to: list)
                // The pack has no Zhuyin data of its own.
                for name in PinyinScheme.zhuyinData { try? fm.removeItem(at: pack.appendingPathComponent(name)) }
            }
            if zhuyinLinked { try store.linkData(.chinesePinyin, from: ZhuyinSchemaTests.data, names: PinyinScheme.zhuyinData) }
            compiledBefore = compiled
        }

        /// The schemas (and the schema list) compiled in the user folder's `build/`.
        var compiled: Set<String> {
            Set(((try? FileManager.default.contentsOfDirectory(atPath: user.appendingPathComponent("build").path)) ?? [])
                .filter { $0.hasSuffix(".yaml") })
        }

        /// The schema list and the patches for `scheme` written (`RimeFuzzy.write`); whether a deployment needs them.
        @discardableResult
        func write(_ scheme: PinyinScheme, fuzzy: [String]) throws -> Bool {
            let listed = try PinyinScheme.applySchemaList(scheme, userDir: user)
            let patch = try FuzzyPinyin.apply(fuzzy, characters: .simplified, scheme: scheme,
                                              schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
            return listed == .written || patch == .written || patch == .removed
        }

        /// librime started as the app starts it, its logs in `logs`, and its deployment waited for.
        func launch(_ scheme: PinyinScheme, logs: String) throws {
            let changed = try write(scheme, fuzzy: [])
            try RimeService.shared.start(sharedDataDir: pack, userDataDir: user, logDir: root.appendingPathComponent(logs),
                                         fullCheck: changed, openCCDir: TraditionalChineseRimeTests.openCC)
            try #require(RimeService.shared.waitUntilReady(timeout: 180))
            #expect(RimeService.shared.deploymentStatus != .failed)
        }

        /// A change in the settings as `RimeFuzzy.apply` makes it: written, and deployed again when it changed.
        func settle(_ scheme: PinyinScheme, fuzzy: [String]) {
            if (try? write(scheme, fuzzy: fuzzy)) == true { RimeService.shared.redeploy() }
        }

        /// librime's log lines in `logs` (its INFO log has the warnings and errors too): no error, and no warning that a
        /// file it had compiled (`compiledBefore`) is missing.
        func checkLogs(_ logs: String) throws {
            let folder = root.appendingPathComponent(logs)
            var lines: [String] = []
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.contains(".INFO.") {
                lines += try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8).split(separator: "\n").map(String.init)
            }
            let errors = lines.filter { $0.range(of: #"^E\d{8} "#, options: .regularExpression) != nil }
            #expect(errors.isEmpty, "\(errors.prefix(5))")
            let missing = lines.filter { line in
                line.hasPrefix("W") && compiledBefore.contains { line.contains("nonexistent config file") && line.contains("/Rime/build/\($0)'") }
            }
            #expect(missing.isEmpty, "\(missing.prefix(5))")
        }
    }
}
