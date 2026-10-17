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

/// Interface text in other languages than Simplified Chinese and English: the translations the Makefile compiles from
/// Resources/Localizable.xcstrings into each app's `<code>.lproj/Localizable.strings`, looked up by the English format,
/// or by a key of its own where one English text has two meanings (`tr(_:_:key:)`).
public enum InterfaceText {
    /// The translation of `english` in `bundle` (a `<code>.lproj` bundle, or a bundle whose localization is
    /// already chosen), filled in with english's arguments; nil when the bundle has no entry for english.format.
    /// A translation whose placeholders don't fit the arguments (more arguments referenced than given, or anything
    /// but %@ / %n$@ / %%) gives nil: never crash on a bad catalog.
    public static func translate(_ english: UIString, in bundle: Bundle) -> String? {
        translate(english, key: english.format, in: bundle)
    }

    /// `translate`, with the catalog entry named by `key` rather than by english.format.
    public static func translate(_ english: UIString, key: String, in bundle: Bundle) -> String? {
        // Returned as is when the table has no entry; a translation can't be one control character.
        let missing = "\u{1}"
        let translation = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
        guard translation != missing else { return nil }
        return fill(translation, english.arguments)
    }

    /// The text in the interface language `language` (`InterfaceLanguage`): `chinese` for Simplified Chinese,
    /// `english` for English, else the translation in `app`'s `<language>.lproj` (by `key`, if given), or `english`
    /// without one.
    public static func text(_ chinese: UIString, _ english: UIString, key: String? = nil, language: String,
                            app: Bundle = .main) -> String {
        switch language {
        case "zh-Hans": return chinese.text
        case "en": return english.text
        default:
            guard let bundle = bundle(language, app: app) else { return english.text }
            return translate(english, key: key ?? english.format, in: bundle) ?? english.text
        }
    }

    /// `app`'s `<language>.lproj`, nil when it has none.
    public static func bundle(_ language: String, app: Bundle = .main) -> Bundle? {
        app.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// `format` with `arguments` filled in by String(format:), when its placeholders are only %@, %n$@ and %% and
    /// refer to no more arguments than there are; else nil.
    public static func fill(_ format: String, _ arguments: [String]) -> String? {
        guard format.contains("%") else { return format }
        var sequential = 0, highest = 0
        var scalars = format.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "%" else { continue }
            var digits = ""
            var next = scalars.next()
            while let digit = next, ("0"..."9").contains(digit) {
                digits.unicodeScalars.append(digit)
                next = scalars.next()
            }
            switch (digits.isEmpty, next) {
            case (true, "%"?): continue
            case (true, "@"?):
                sequential += 1
                highest = max(highest, sequential)
            case (false, "$"?):
                guard let position = Int(digits), position > 0, scalars.next() == "@" else { return nil }
                highest = max(highest, position)
            default: return nil
            }
        }
        guard highest <= arguments.count else { return nil }
        return String(format: format, arguments: arguments.map { $0 as NSString })
    }
}
