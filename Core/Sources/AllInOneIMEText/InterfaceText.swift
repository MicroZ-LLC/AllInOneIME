import Foundation

/// Text for the interface, written as a literal with interpolations.
///
/// `tr("共 \(n) 个", "\(n) items")` makes two of these: the English one's `format` ("%@ items") is the key in
/// Resources/Localizable.xcstrings, and other languages translate that format (`InterfaceText.translate`).
public struct UIString: ExpressibleByStringInterpolation, Equatable, Sendable {
    /// The literal with "%@" for each interpolation, in order, and "%" written as "%%" (a printf format, as
    /// String(format:) and the String Catalog use).
    public var format: String
    /// Each interpolation, as text (`"\(value)"`).
    public var arguments: [String]

    /// A runtime string: format is the string with "%" doubled; no arguments.
    public init(_ string: String) {
        format = string.replacingOccurrences(of: "%", with: "%%")
        arguments = []
    }

    public init(stringLiteral value: String) { self.init(value) }

    public init(stringInterpolation: Interpolation) {
        format = stringInterpolation.format
        arguments = stringInterpolation.arguments
    }

    /// The text: format with the arguments filled in.
    public var text: String { InterfaceText.fill(format, arguments) ?? format }

    /// One text after the other: a literal broken over lines (`tr("…" + "…", "…" + "…")`).
    public static func + (lhs: UIString, rhs: UIString) -> UIString {
        var joined = lhs
        joined.format += rhs.format
        joined.arguments += rhs.arguments
        return joined
    }

    public struct Interpolation: StringInterpolationProtocol {
        var format = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            format.reserveCapacity(literalCapacity + 2 * interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) { format += literal.replacingOccurrences(of: "%", with: "%%") }

        public mutating func appendInterpolation<T>(_ value: T) {
            format += "%@"
            arguments.append("\(value)")
        }
    }
}

/// Interface text in other languages than Simplified Chinese and English: the translations of
/// Resources/Localizable.xcstrings, looked up by the English format, or by a key of its own where one English text has
/// two meanings (`tr(_:_:key:)`).
///
/// Where they come from is the shell's business (`lookup`): on Apple platforms the `<code>.lproj/Localizable.strings`
/// the Makefile compiles from the catalog into each app (`bundleLookup`); elsewhere (Windows, Android, Linux) the catalog
/// itself, read into a table per language (`StringCatalog`, `tableLookup`). The core only ever asks `text` in a language.
public enum InterfaceText {
    /// The translated format of a catalog key (the English format, or a key of its own) in a language; nil without one.
    public typealias Lookup = @Sendable (_ key: String, _ language: String) -> String?

    /// The translations `text(_:_:key:language:)` uses, for the whole process: the app's own `tr` and the core's texts
    /// that take a language code. Set by the shell when it starts (the input method: `bundleLookup(app:)` on its bundle).
    /// Until then there are none, and every language but Simplified Chinese shows English.
    public static var lookup: Lookup {
        get { current.withLock { $0 } ?? { _, _ in nil } }
        set { current.withLock { $0 = newValue } }
    }

    /// Whether a shell (or `UIText`) has set `lookup`: `UIText` hands it the app's `.lproj` bundles on its first read
    /// unless one is set already (a shell that has tables instead, `tableLookup`).
    public static var lookupInstalled: Bool { current.withLock { $0 != nil } }

    private static let current = Locked<Lookup?>(initialState: nil)

    /// The translation of `english` in `bundle` (a `<code>.lproj` bundle, or a bundle whose localization is
    /// already chosen), filled in with english's arguments; nil when the bundle has no entry for english.format.
    /// A translation whose placeholders don't fit the arguments (more arguments referenced than given, or anything
    /// but %@ / %n$@ / %%) gives nil: never crash on a bad catalog.
    public static func translate(_ english: UIString, in bundle: Bundle) -> String? {
        translate(english, key: english.format, in: bundle)
    }

    /// `translate`, with the catalog entry named by `key` rather than by english.format.
    public static func translate(_ english: UIString, key: String, in bundle: Bundle) -> String? {
        format(key, in: bundle).flatMap { fill($0, english.arguments) }
    }

    /// The translation of `english` in `table` (one language's, catalog key → translated format: `StringCatalog.table`),
    /// filled in with english's arguments, as `translate(_:in:)` does from a bundle: nil without an entry, or when the
    /// entry's placeholders don't fit.
    public static func translate(_ english: UIString, in table: [String: String]) -> String? {
        translate(english, key: english.format, in: table)
    }

    /// `translate(_:in:)` from a table, with the entry named by `key` rather than by english.format.
    public static func translate(_ english: UIString, key: String, in table: [String: String]) -> String? {
        table[key].flatMap { fill($0, english.arguments) }
    }

    /// The text in the interface language `language` (`InterfaceLanguage`): `chinese` for Simplified Chinese,
    /// `english` for English, else the translation `lookup` has (by `key`, if given), or `english` without one.
    public static func text(_ chinese: UIString, _ english: UIString, key: String? = nil, language: String) -> String {
        switch language {
        case "zh-Hans": return chinese.text
        case "en": return english.text
        default: return text(chinese, english, key: key, language: language, lookup: lookup)
        }
    }

    /// `text`, with the translations from `lookup` rather than the process's.
    public static func text(_ chinese: UIString, _ english: UIString, key: String? = nil, language: String,
                            lookup: Lookup) -> String {
        switch language {
        case "zh-Hans": return chinese.text
        case "en": return english.text
        default: return lookup(key ?? english.format, language).flatMap { fill($0, english.arguments) } ?? english.text
        }
    }

    /// `text`, with the translations in `app`'s `<language>.lproj`.
    public static func text(_ chinese: UIString, _ english: UIString, key: String? = nil, language: String,
                            app: Bundle) -> String {
        switch language {
        case "zh-Hans": return chinese.text
        case "en": return english.text
        default:
            guard let bundle = bundle(language, app: app) else { return english.text }
            return translate(english, key: key ?? english.format, in: bundle) ?? english.text
        }
    }

    /// `app`'s `<language>.lproj`, nil when it has none.
    public static func bundle(_ language: String, app: Bundle) -> Bundle? {
        app.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// The translations in `app`'s `<code>.lproj` bundles (Apple platforms), each language's bundle found once.
    public static func bundleLookup(app: Bundle) -> Lookup {
        let bundles = Locked<(app: Bundle, found: [String: Bundle?])>(initialState: (app, [:]))
        return { key, language in
            let lproj = bundles.withLock { state -> Bundle? in
                if let found = state.found[language] { return found }
                let found = bundle(language, app: state.app)
                state.found[language] = found
                return found
            }
            return lproj.flatMap { format(key, in: $0) }
        }
    }

    /// The translations in `tables`, language → catalog key → translated format (`StringCatalog.tables`): for the
    /// shells without `.lproj` bundles.
    public static func tableLookup(_ tables: [String: [String: String]]) -> Lookup {
        { key, language in tables[language]?[key] }
    }

    /// The translated format of `key` in `bundle`'s Localizable table; nil without an entry.
    static func format(_ key: String, in bundle: Bundle) -> String? {
        // Returned as is when the table has no entry; a translation can't be one control character.
        let missing = "\u{1}"
        let translation = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
        return translation == missing ? nil : translation
    }

    /// `format` with `arguments` filled in, when its placeholders are only %@ (the next argument), %n$@ (the n-th) and
    /// %% (a "%"), and refer to no more arguments than there are; else nil. Filled in here rather than by
    /// String(format:), whose handling differs between Apple's Foundation and swift-corelibs-foundation.
    public static func fill(_ format: String, _ arguments: [String]) -> String? {
        guard format.contains("%") else { return format }
        var text = ""
        var sequential = 0
        var scalars = format.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "%" else {
                text.unicodeScalars.append(scalar)
                continue
            }
            var digits = ""
            var next = scalars.next()
            while let digit = next, ("0"..."9").contains(digit) {
                digits.unicodeScalars.append(digit)
                next = scalars.next()
            }
            let index: Int
            switch (digits.isEmpty, next) {
            case (true, "%"?):
                text += "%"
                continue
            case (true, "@"?):
                index = sequential
                sequential += 1
            case (false, "$"?):
                guard let position = Int(digits), position > 0, scalars.next() == "@" else { return nil }
                index = position - 1
            default: return nil
            }
            guard index < arguments.count else { return nil }
            text += arguments[index]
        }
        return text
    }
}

/// Interface text in one language, for code that has no `tr` of its own (the core's texts): `t.tr("中文", "English")`
/// gives what the app's `tr` would in `language`, through `InterfaceText.lookup`.
public struct InterfaceWords: Sendable {
    /// The interface language's code (`InterfaceLanguage`): "zh-Hans", "en", …
    public var language: String

    public init(language: String) { self.language = language }

    /// Simplified Chinese or English.
    public init(chinese: Bool) { language = InterfaceLanguage.code(chinese: chinese) }

    /// Whether the language is Chinese: what only comes in Chinese and English is Chinese then.
    public var chinese: Bool { InterfaceLanguage.isChinese(language) }

    /// The Chinese, the English, or the translation of the English (by `key`, if given).
    public func tr(_ chinese: UIString, _ english: UIString, key: String? = nil) -> String {
        InterfaceText.text(chinese, english, key: key, language: language)
    }
}

/// A value behind a lock, like `OSAllocatedUnfairLock(initialState:)` (Apple-only) or `Mutex` (macOS 15): an `NSLock`,
/// which every Foundation has. A class, so copies share the value. The interface text's (the process-wide lookup, the
/// bundles a lookup has found, `UIText`'s state) and, through AllInOneIMECore's re-export, the core's and the shells'.
public final class Locked<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    public init(initialState: State) {
        state = initialState
    }

    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
