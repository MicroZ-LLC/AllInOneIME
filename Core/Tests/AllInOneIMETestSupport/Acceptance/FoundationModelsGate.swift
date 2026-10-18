import Foundation

// "macOS 14 safety" (the AppleModel acceptance tests' S10): the app runs on macOS 14 although it can use Apple's
// on-device model (FoundationModels, macOS 26+). Besides the weak link, that takes every use of the framework's symbols
// being inside `#if canImport(FoundationModels)` and inside a macOS 26+ availability check (an import line needs only
// the first). One rule for the core's sources (s10) and the macOS shell's (s10b), so it is here, once.

public enum FoundationModelsGate {
    /// What of FoundationModels a line can use: the framework, its types, and the core's backend built on them.
    public static let symbols = ["FoundationModels", "SystemLanguageModel", "LanguageModelSession", "GenerationOptions",
                                 "Transcript", "LanguageModelError", "FoundationModelsBackend"]

    public struct Scan: Sendable {
        /// The Swift files read.
        public var files = 0
        /// The lines that use a symbol.
        public var uses = 0
        /// The uses outside the gate, "File.swift:12: the line (what it lacks)".
        public var offences: [String] = []

        public init() {}
    }

    /// Every Swift file under `folder`, subfolders too.
    public static func scan(_ folder: URL) throws -> Scan {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var scan = Scan()
        scan.files = files.count
        for file in files {
            try check(String(contentsOf: file, encoding: .utf8), name: file.lastPathComponent, into: &scan)
        }
        return scan
    }

    /// A file's text, by `name`.
    public static func check(_ text: String, name: String, into scan: inout Scan) {
        let lines = text.components(separatedBy: "\n")
        var gate: [String] = []  // the #if conditions around the line (an #else or #elseif branch is not its #if's)
        var available = false  // inside a declaration or block marked for macOS 26 or later
        var depth = 0, availableDepth = Int.max
        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") { gate.append(trimmed) }
            if trimmed.hasPrefix("#elseif ") || trimmed == "#else" || trimmed.hasPrefix("#else ") {
                if !gate.isEmpty { gate[gate.count - 1] = trimmed }
            }
            if trimmed.hasPrefix("#endif") { _ = gate.popLast() }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { continue }
            if line.range(of: #"[@#]available\(macOS (2[6-9]|[3-9][0-9])"#, options: .regularExpression) != nil {
                if !available { availableDepth = depth }
                available = true
            }
            let code = line.components(separatedBy: "//").first ?? line
            let used = symbols.filter { symbol in
                code.range(of: "\\b\(symbol)\\b", options: .regularExpression) != nil
            }
            // `AppleModel.system`'s stand-in names the type inside the gate; a comment or string isn't a use.
            if !used.isEmpty, !code.contains("\"") {
                scan.uses += 1
                let where_ = "\(name):\(number + 1): \(trimmed)"
                if !gate.contains("#if canImport(FoundationModels)") {
                    scan.offences.append("\(where_) (not inside #if canImport(FoundationModels))")
                }
                if !isImport(trimmed), !available {
                    scan.offences.append("\(where_) (no macOS 26 availability check)")
                }
            }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if available, depth <= availableDepth, line.contains("}") { available = false; availableDepth = .max }
        }
    }

    /// An import line, its attributes too: `import FoundationModels`, `@_weakLinked import FoundationModels`,
    /// `@preconcurrency import …`.
    public static func isImport(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^(@[A-Za-z_][A-Za-z0-9_]*\s+)*import\s"#, options: .regularExpression) != nil
    }
}
