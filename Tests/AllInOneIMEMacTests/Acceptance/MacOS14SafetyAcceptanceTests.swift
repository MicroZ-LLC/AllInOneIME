import Foundation
import Testing

// "macOS 14 safety", the macOS shell's part (s10b; the core's part is the AppleModel acceptance tests' s10): the shipped
// app runs on macOS 14 even though it can use Apple's on-device model (FoundationModels, macOS 26+). So FoundationModels
// is weak-linked in every shipped binary that links the core (the input method AllInOneIME, allinoneime-cli and the
// installer): the core's package carries no linker flags (a package depended on by URL may not use unsafeFlags), so
// this package's manifest passes `-Xlinker -weak_framework -Xlinker FoundationModels` to each of them. And nothing of
// FoundationModels is used in the shell outside `#if canImport(FoundationModels)` and a macOS 26+ availability check.
// Written from the spec by the acceptance tests' author.

enum MacOS14Safety {
    /// This package's root (Tests/AllInOneIMEMacTests/Acceptance/ is three folders down).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The shipped executables that link the core.
    static let shipped = ["AllInOneIME", "allinoneime-cli", "AllInOneIMEInstaller"]

    /// The weak link, as `unsafeFlags` takes it.
    static let flag = #""-Xlinker"\s*,\s*"-weak_framework"\s*,\s*"-Xlinker"\s*,\s*"FoundationModels""#

    static func manifest() throws -> String {
        try Manifest.code(String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8))
    }

    /// The built binaries of those executables there are: ALLINONEIME_TEST_BINARY (the input method's debug build, as
    /// `make test` names it to the core's tests), this package's debug and release builds, and the apps `make` puts in
    /// build/.
    static var binaries: [URL] {
        var found: [URL] = []
        func add(_ url: URL) {
            let url = url.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: url.path), !found.contains(url) else { return }
            found.append(url)
        }
        if let named = ProcessInfo.processInfo.environment["ALLINONEIME_TEST_BINARY"], !named.isEmpty {
            add(URL(fileURLWithPath: named))
        }
        for configuration in ["debug", "release"] {
            for name in shipped { add(root.appendingPathComponent(".build/\(configuration)/\(name)")) }
        }
        let build = root.appendingPathComponent("build")
        let apps = (try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? []
        for app in apps where app.pathExtension == "app" {
            for name in shipped { add(app.appendingPathComponent("Contents/MacOS/\(name)")) }
        }
        return found
    }

    /// Each FoundationModels entry's load command in `binary`'s `otool -l -arch all`, one per architecture.
    static func foundationModelsLoads(_ binary: URL) throws -> [String] {
        let otool = Process()
        otool.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otool.arguments = ["-l", "-arch", "all", binary.path]
        let output = Pipe()
        otool.standardOutput = output
        otool.standardError = FileHandle.nullDevice
        try otool.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        otool.waitUntilExit()
        #expect(otool.terminationStatus == 0, "otool -l \(binary.path) failed")
        var command = "", loads: [String] = []
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            let words = line.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count >= 2 else { continue }
            if words[0] == "cmd" { command = String(words[1]) }
            if words[0] == "name", words[1].contains("/FoundationModels.framework/") { loads.append(command) }
        }
        return loads
    }
}

/// Just enough of reading a manifest: the code without comments, a call's arguments, the targets, and what a `let`
/// stands for.
enum Manifest {
    /// `text` without its comments (`//` and `/* */`); string literals are kept as they are.
    static func code(_ text: String) -> String {
        var out = "", chars = Array(text), i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i], next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if inString {
                out.append(c)
                if c == "\\", let next { out.append(next); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
            } else if c == "\"" {
                inString = true; out.append(c); i += 1
            } else if c == "/", next == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "/", next == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else {
                out.append(c); i += 1
            }
        }
        return out
    }

    /// The text from `open` (an index of "(" or "[") to its closing bracket, both included; strings are skipped over.
    static func balanced(_ code: [Character], from open: Int) -> String? {
        var depth = 0, i = open, inString = false
        while i < code.count {
            let c = code[i]
            if inString {
                if c == "\\" { i += 2; continue }
                if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "(" || c == "[" {
                depth += 1
            } else if c == ")" || c == "]" {
                depth -= 1
                if depth == 0 { return String(code[open...i]) }
            }
            i += 1
        }
        return nil
    }

    /// Every target declaration (`.target(…)`, `.executableTarget(…)`, `.testTarget(…)`): its kind, name and
    /// arguments.
    static func targets(_ code: String) -> [(kind: String, name: String, arguments: String)] {
        let chars = Array(code)
        let pattern = try! NSRegularExpression(pattern: #"\.(target|executableTarget|testTarget)\s*\("#)
        let ns = code as NSString
        var out: [(String, String, String)] = []
        for match in pattern.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: match.range(at: 1))
            // The "(": the match's last character (as a Character index: the manifest's text before it, counted).
            let open = (ns.substring(to: match.range.location + match.range.length) as String).count - 1
            guard let arguments = balanced(chars, from: open),
                  let name = arguments.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression)
                    .map({ String(arguments[$0]) })?.components(separatedBy: "\"").dropFirst().first
            else { continue }
            out.append((kind, name, arguments))
        }
        return out
    }

    /// The value of the `label:` argument in `arguments` (`[…]` or `(…)` after it, or a name), if it has one.
    static func argument(_ label: String, in arguments: String) -> String? {
        guard let range = arguments.range(of: #"\b\#(label):\s*"#, options: .regularExpression) else { return nil }
        let chars = Array(arguments)
        let start = arguments.distance(from: arguments.startIndex, to: range.upperBound)
        guard start < chars.count else { return nil }
        if chars[start] == "[" || chars[start] == "(" { return balanced(chars, from: start) }
        let name = chars[start...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// The names of the top-level `let`s whose value carries `pattern` (a regular expression), or names a `let` that
    /// does.
    static func carriers(of pattern: String, in code: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"(?m)^\s*(?:public\s+|private\s+|fileprivate\s+)?let\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*"#)
        let ns = code as NSString
        // Each let's value: from its "=" to the end of its statement (brackets balanced, up to a line that doesn't
        // continue it).
        var values: [(String, String)] = []
        for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let rest = ns.substring(from: match.range.location + match.range.length)
            // The package itself holds every target's settings: it isn't a setting a target can name.
            if rest.hasPrefix("Package(") { continue }
            var depth = 0, value = ""
            for line in rest.components(separatedBy: "\n") {
                value += line + "\n"
                depth += line.filter { "([".contains($0) }.count - line.filter { ")]".contains($0) }.count
                if depth <= 0 { break }
            }
            values.append((name, value))
        }
        var found = Set<String>()
        var changed = true
        while changed {
            changed = false
            for (name, value) in values where !found.contains(name) {
                if value.range(of: pattern, options: .regularExpression) != nil
                    || found.contains(where: { value.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
                    found.insert(name)
                    changed = true
                }
            }
        }
        return found
    }

    /// Whether `settings` (a target's linkerSettings) passes `pattern`, itself or through one of `carriers`.
    static func passes(_ settings: String, _ pattern: String, carriers: Set<String>) -> Bool {
        if settings.range(of: #"unsafeFlags\(\s*\[[^\]]*"# + pattern, options: .regularExpression) != nil { return true }
        return carriers.contains { settings.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
    }
}

@Suite("MacOS14SafetyAcceptance")
struct MacOS14SafetyAcceptanceTests {
    typealias S = MacOS14Safety

    /// The root manifest declares macOS 14 and passes the weak link to AllInOneIME, allinoneime-cli and
    /// AllInOneIMEInstaller (in the target's linkerSettings, itself or through a shared `let`), and to every other
    /// executable or test target that links the core (anything of it but AllInOneIMEText, or the shell's library on it).
    @Test func s10b_rootManifestWeakLinksFoundationModels() throws {
        let code = try S.manifest()
        #expect(code.contains(#"name: "AllInOneIME""#), "the root here should be the macOS shell's: \(S.root.path)")
        #expect(code.range(of: #"platforms:\s*\[[^\]]*\.macOS\(\.v14\)"#, options: .regularExpression) != nil,
                "Package.swift should declare .macOS(.v14)")
        // A flag spelt the other way (one -Wl, string, or -weak_framework without -Xlinker) doesn't count.
        let carriers = Manifest.carriers(of: #"unsafeFlags\(\s*\[[^\]]*"# + S.flag, in: code)
        let targets = Manifest.targets(code)
        for name in S.shipped {
            let target = try #require(targets.first { $0.name == name }, "no target \(name) in Package.swift")
            #expect(target.kind == "executableTarget", "\(name) should be an executable target")
            let settings = Manifest.argument("linkerSettings", in: target.arguments) ?? ""
            #expect(Manifest.passes(settings, S.flag, carriers: carriers),
                    "\(name)'s linkerSettings should pass -Xlinker -weak_framework -Xlinker FoundationModels")
        }
        for target in targets where target.kind != "target" && !S.shipped.contains(target.name) {
            let dependencies = Manifest.argument("dependencies", in: target.arguments) ?? ""
            let linksCore = dependencies.range(of: #"core\("AllInOneIME(Core|CLI|Rime|TestSupport)"\)|"AllInOneIMEMac""#,
                                               options: .regularExpression) != nil
            guard linksCore else { continue }
            let settings = Manifest.argument("linkerSettings", in: target.arguments) ?? ""
            #expect(Manifest.passes(settings, S.flag, carriers: carriers),
                    "\(target.name) links the core and should weak-link FoundationModels too")
        }
    }

    /// The reading above, on manifests of its own: a flag in the target or in a shared `let` counts, one in a comment,
    /// in swiftSettings, or in another target doesn't.
    @Test func s10b_theManifestReading() {
        func passes(_ manifest: String, _ name: String) -> Bool {
            let code = Manifest.code(manifest)
            let carriers = Manifest.carriers(of: #"unsafeFlags\(\s*\[[^\]]*"# + S.flag, in: code)
            guard let target = Manifest.targets(code).first(where: { $0.name == name }) else { return false }
            return Manifest.passes(Manifest.argument("linkerSettings", in: target.arguments) ?? "", S.flag, carriers: carriers)
        }
        let inline = #"""
            .executableTarget(name: "A", dependencies: [core("AllInOneIMECore")],
                linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]),
            .executableTarget(name: "B", dependencies: [], linkerSettings: [.linkedFramework("AppKit")]),
            """#
        #expect(passes(inline, "A"))
        #expect(!passes(inline, "B"))
        let shared = #"""
            let weak = LinkerSetting.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"],
                                                 .when(platforms: [.macOS]))
            let both = [weak, .linkedFramework("AppKit")]
            let other = LinkerSetting.unsafeFlags(["-L/x"])
            .executableTarget(name: "A", linkerSettings: [weak]),
            .executableTarget(name: "C", linkerSettings: both),
            .executableTarget(name: "B", linkerSettings: [other]),
            """#
        #expect(passes(shared, "A"))
        #expect(passes(shared, "C"))
        #expect(!passes(shared, "B"))
        // The package (whose targets carry the flag) is not a carrier: a target naming `package` doesn't pass.
        let named = #"""
            let weak = LinkerSetting.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            let package = Package(name: "P", targets: [
                .executableTarget(name: "A", linkerSettings: [weak]),
                .executableTarget(name: "B", linkerSettings: [.unsafeFlags(["-DX"]), package.x]),
            ])
            """#
        #expect(passes(named, "A"))
        #expect(!passes(named, "B"))
        let commented = #"""
            // .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            .executableTarget(name: "A", swiftSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])],
                              linkerSettings: [/* .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]) */]),
            """#
        #expect(!passes(commented, "A"))
    }

    /// Nothing of FoundationModels in the shell's sources outside `#if canImport(FoundationModels)` and a macOS 26+
    /// availability check: the same rule as the core's (s10).
    @Test func s10b_rootSourcesAreGated() throws {
        let scan = try FoundationModelsGate.scan(S.root.appendingPathComponent("Sources"))
        #expect(scan.files > 50, "too few sources at \(S.root.path)/Sources: \(scan.files)")
        for offence in scan.offences { Issue.record("FoundationModels \(offence)") }
    }

    /// The binaries as built: FoundationModels under LC_LOAD_WEAK_DYLIB in each, never LC_LOAD_DYLIB. Skipped, saying
    /// so, when nothing is built yet (`make test` builds the input method first).
    @Test(.enabled(if: !MacOS14Safety.binaries.isEmpty,
                   "no built binary: neither ALLINONEIME_TEST_BINARY, .build/debug or .build/release, nor build/*.app"))
    func s10b_builtBinariesWeakLinkFoundationModels() throws {
        let binaries = S.binaries
        print("s10b: otool -l on \(binaries.map(\.path).joined(separator: ", "))")
        for binary in binaries {
            let loads = try S.foundationModelsLoads(binary)
            #expect(!loads.isEmpty, "\(binary.path) doesn't link FoundationModels at all")
            #expect(loads.allSatisfy { $0 == "LC_LOAD_WEAK_DYLIB" },
                    "\(binary.path) links FoundationModels strongly: \(loads)")
            #expect(!loads.contains("LC_LOAD_DYLIB"), "\(binary.path) has FoundationModels under LC_LOAD_DYLIB")
        }
    }
}
