import Foundation
import AllInOneIMEScriptEngine
internal import CQuickJS

/// A value of a `QuickJSContext`, converted as JavaScriptCore converts its own (`JSValue`): what a script sees of
/// Swift's values and Swift of a script's is the same with either engine.
final class QuickJSValue: ScriptValue {
    let runtime: QuickJSRuntime
    /// QuickJS's value, this one's to free.
    let value: JSValue

    init(_ runtime: QuickJSRuntime, _ value: JSValue) {
        self.runtime = runtime
        self.value = value
    }

    deinit { JS_FreeValueRT(runtime.rt, value) }

    var isUndefined: Bool { JS_IsUndefined(value) }
    var isObject: Bool { JS_IsObject(value) }
    var isString: Bool { JS_IsString(value) }
    var isNumber: Bool { JS_IsNumber(value) }
    var boolValue: Bool { JS_ToBool(runtime.ctx, value) == 1 }

    var numberValue: Double? {
        guard isNumber else { return nil }
        var number = 0.0
        JS_ToFloat64(runtime.ctx, &number, value)
        return number
    }

    func toString() -> String? {
        runtime.enter {
            let text = runtime.string(value)
            if text == nil { runtime.takeException() }
            return text
        }
    }

    /// As JavaScriptCore's `toArray`: any object by its `length`, nil for null and undefined, and for anything else nil
    /// with a TypeError for the exception.
    func toArray() -> [Any]? {
        runtime.enter {
            if JS_IsObject(value) {
                var ancestors = [value]
                return runtime.items(of: value, ancestors: &ancestors)
            }
            if !JS_IsNull(value) && !JS_IsUndefined(value) { runtime.throwError(.type, "Cannot convert primitive to NSArray") }
            return nil
        }
    }

    /// As JavaScriptCore's `toDictionary`: any object's enumerable properties, its prototypes' too (as `for … in` has
    /// them); nil for null and undefined, and for anything else nil with a TypeError for the exception.
    func toDictionary() -> [String: Any]? {
        runtime.enter {
            if JS_IsObject(value) {
                var ancestors = [value]
                return runtime.properties(of: value, ancestors: &ancestors)
            }
            if !JS_IsNull(value) && !JS_IsUndefined(value) { runtime.throwError(.type, "Cannot convert primitive to NSDictionary") }
            return nil
        }
    }

    func property(_ name: String) -> (any ScriptValue)? {
        runtime.enter { runtime.wrap(JS_GetPropertyStr(runtime.ctx, value, name)) }
    }

    func call(_ arguments: [Any]) -> (any ScriptValue)? {
        runtime.run {
            var values = arguments.map { runtime.makeValue($0) }
            defer { values.forEach { JS_FreeValue(runtime.ctx, $0) } }
            return JS_Call(runtime.ctx, value, QJS_Undefined(), Int32(values.count), &values)
        }
    }
}

// MARK: - Swift's values to a script's

extension QuickJSRuntime {
    /// How deep a value is converted, either way, at most: a container nested deeper (or one inside itself, or one past
    /// the thread's `stackFloor`) converts empty.
    static let maxDepth = 256
    /// The most items `toArray` reads of an object's `length`, so that `{length: 4e9}` doesn't take all memory.
    static let maxItems = 1 << 20
    /// A property as an assignment makes it (JS_PROP_C_W_E, a macro Swift can't read).
    static let field = Int32(JS_PROP_CONFIGURABLE | JS_PROP_WRITABLE | JS_PROP_ENUMERABLE)

    /// `value` as a new value of this runtime (the caller's to free), as JavaScriptCore converts an object
    /// (`JSValue(object:in:)`): text, numbers, Bools (Foundation's true and false too), arrays, dictionaries, NSNull and
    /// nil in them (null), dates, and this engine's `ScriptValue`s; nil itself, and anything else, is undefined.
    func makeValue(_ value: Any?, depth: Int = 0) -> JSValue {
        guard let value else { return QJS_Undefined() }
        if let value = value as? QuickJSValue {
            if value.runtime === self { return JS_DupValue(ctx, value.value) }
            // Another context's (each has a runtime of its own): what Swift makes of it.
            return makeValue(value.runtime.enter { value.runtime.object(of: value.value) }, depth: depth)
        }
        guard depth < Self.maxDepth, ThreadStack.here() > stackFloor else { return QJS_Undefined() }
        switch value {
        case let text as String:
            return newString(text)
        case let text as Substring:
            return newString(String(text))
        case let number as NSNumber where type(of: value) is NSNumber.Type:
            if number.isBoolean { return JS_NewBool(ctx, number.boolValue) }
            return JS_NewFloat64(ctx, number.doubleValue)
        case let flag as Bool:
            return JS_NewBool(ctx, flag)
        case let integer as any BinaryInteger:
            if let exact = Int64(exactly: integer) { return JS_NewInt64(ctx, exact) }
            return JS_NewFloat64(ctx, Double(integer))
        case let number as any BinaryFloatingPoint:
            return JS_NewFloat64(ctx, Double(number))
        case let items as [Any]:
            let array = JS_NewArray(ctx)
            guard !JS_IsException(array) else { return failed() }
            for (index, item) in items.enumerated() {
                JS_DefinePropertyValueUint32(ctx, array, UInt32(index), makeValue(item, depth: depth + 1), Self.field)
            }
            return array
        case let fields as [String: Any]:
            return makeObject(fields.map { ($0.key, $0.value) }, depth: depth)
        case let fields as [AnyHashable: Any]:
            return makeObject(fields.map { ("\($0.key.base)", $0.value) }, depth: depth)
        case is NSNull:
            return QJS_Null()
        case let date as Date:
            let made = JS_NewDate(ctx, date.timeIntervalSince1970 * 1000)
            return JS_IsException(made) ? failed() : made
        default:
            // nil in an array or a dictionary (an Optional's none) is null there, as Foundation bridges it.
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle == .optional else { return QJS_Undefined() }
            return mirror.children.first.map { makeValue($0.value, depth: depth) } ?? QJS_Null()
        }
    }

    /// An object of `fields`, each its own property (a "__proto__" key too: defined, not set).
    private func makeObject(_ fields: [(String, Any)], depth: Int) -> JSValue {
        let object = JS_NewObject(ctx)
        guard !JS_IsException(object) else { return failed() }
        for (name, item) in fields {
            JS_DefinePropertyValueStr(ctx, object, name, makeValue(item, depth: depth + 1), Self.field)
        }
        return object
    }

    private func newString(_ text: String) -> JSValue {
        var text = text
        let made = text.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { JS_NewStringLen(ctx, $0.baseAddress, $0.count) }
        }
        return JS_IsException(made) ? failed() : made
    }

    /// Out of memory on the way: the exception taken, undefined in the value's place.
    private func failed() -> JSValue {
        takeException()
        return QJS_Undefined()
    }

    /// The errors Swift throws: a TypeError, as JavaScriptCore reports one of its own conversions, or the InternalError
    /// of a script stopped (`run`).
    enum ErrorKind {
        case type, `internal`
    }

    /// An error of `kind` for the exception, made by QuickJS from the realm's own prototype (quickjs-swift.h), never by
    /// calling what a script left in `TypeError` or `InternalError`; null when even that fails (out of memory).
    func throwError(_ kind: ErrorKind, _ message: String) {
        switch kind {
        case .type: _ = QJS_ThrowTypeError(ctx, message)
        case .internal: _ = QJS_ThrowInternalError(ctx, message)
        }
        takeException()
    }
}

// MARK: - A script's values to Swift's

extension QuickJSRuntime {
    /// `value` as JavaScriptCore converts it in an array or a dictionary: text, numbers and Bools as Foundation's
    /// (NSNumber), null as NSNull, dates, arrays and other objects as arrays and dictionaries; nil for undefined, symbols
    /// and BigInts.
    func object(of value: JSValue) -> Any? {
        var ancestors: [JSValue] = []
        return object(of: value, ancestors: &ancestors)
    }

    private func object(of value: JSValue, ancestors: inout [JSValue]) -> Any? {
        if JS_IsBool(value) { return NSNumber(value: JS_ToBool(ctx, value) == 1) }
        if JS_IsNumber(value) {
            var number = 0.0
            JS_ToFloat64(ctx, &number, value)
            return Self.number(number)
        }
        if JS_IsString(value) { return string(value) }
        if JS_IsNull(value) { return NSNull() }
        guard JS_IsObject(value) else { return nil }
        if JS_IsDate(value) {
            var time = Double.nan
            if JS_ToFloat64(ctx, &time, value) < 0 { dropException() }
            return Date(timeIntervalSince1970: time / 1000)
        }
        let array = JS_IsArray(value)
        guard ancestors.count < Self.maxDepth, ThreadStack.here() > stackFloor,
              !ancestors.contains(where: { JS_IsStrictEqual(ctx, $0, value) }) else {
            return array ? [Any]() : [String: Any]() as Any
        }
        ancestors.append(value)
        defer { ancestors.removeLast() }
        return array ? items(of: value, ancestors: &ancestors) : properties(of: value, ancestors: &ancestors)
    }

    /// Items 0 up to the object's `length`, undefined ones as NSNull.
    func items(of value: JSValue, ancestors: inout [JSValue]) -> [Any] {
        var count: UInt32 = 0
        let length = JS_GetPropertyStr(ctx, value, "length")
        if JS_IsException(length) || JS_ToUint32(ctx, &count, length) < 0 { dropException() }
        JS_FreeValue(ctx, length)
        var items: [Any] = []
        for index in 0..<min(Int(count), Self.maxItems) {
            let item = JS_GetPropertyUint32(ctx, value, UInt32(index))
            if JS_IsException(item) { dropException() }
            items.append(object(of: item, ancestors: &ancestors) ?? NSNull())
            JS_FreeValue(ctx, item)
        }
        return items
    }

    /// The enumerable properties with text for names, its own and then its prototypes' (one a prototype shadows left
    /// out), those that are undefined left out.
    func properties(of value: JSValue, ancestors: inout [JSValue]) -> [String: Any] {
        var names: [(String, JSAtom)] = []
        var seen = Set<String>()
        var holder = JS_DupValue(ctx, value)
        while JS_IsObject(holder) {
            var table: UnsafeMutablePointer<JSPropertyEnum>?
            var count: UInt32 = 0
            guard JS_GetOwnPropertyNames(ctx, &table, &count, holder, Int32(JS_GPN_STRING_MASK | JS_GPN_SET_ENUM)) == 0 else {
                dropException()
                break
            }
            for index in 0..<Int(count) {
                guard let entry = table?[index], let name = atomName(entry.atom), seen.insert(name).inserted,
                      entry.is_enumerable else { continue }
                names.append((name, JS_DupAtom(ctx, entry.atom)))
            }
            JS_FreePropertyEnum(ctx, table, count)
            let prototype = JS_GetPrototype(ctx, holder)
            if JS_IsException(prototype) { dropException() }
            JS_FreeValue(ctx, holder)
            holder = prototype
        }
        JS_FreeValue(ctx, holder)
        var fields: [String: Any] = [:]
        for (name, atom) in names {
            let field = JS_GetProperty(ctx, value, atom)
            if JS_IsException(field) { dropException() }
            if let converted = object(of: field, ancestors: &ancestors) { fields[name] = converted }
            JS_FreeValue(ctx, field)
            JS_FreeAtom(ctx, atom)
        }
        return fields
    }

    private func atomName(_ atom: JSAtom) -> String? {
        guard let name = JS_AtomToCString(ctx, atom) else {
            dropException()
            return nil
        }
        defer { JS_FreeCString(ctx, name) }
        return String(cString: name)
    }

    /// A string's text (or what `String(value)` makes of anything else); nil when that throws (the exception is left
    /// pending for the caller).
    func string(_ value: JSValue) -> String? {
        var length = 0
        guard let text = JS_ToCStringLen(ctx, &length, value) else { return nil }
        defer { JS_FreeCString(ctx, text) }
        return String(decoding: UnsafeRawBufferPointer(start: text, count: length), as: UTF8.self)
    }

    /// A number as JavaScriptCore gives it (NSNumber); a whole one as an integer, which prints as JavaScript prints it
    /// with every Foundation ("1"; swift-corelibs-foundation prints a double's "1.0").
    static func number(_ value: Double) -> NSNumber {
        if value.rounded() == value, abs(value) <= 9_007_199_254_740_992 { return NSNumber(value: Int64(value)) }
        return NSNumber(value: value)
    }
}

extension NSNumber {
    /// Foundation's true or false (CFBoolean on Apple platforms), not the numbers 1 and 0: the two instances
    /// `NSNumber(value:)` gives back for a Bool (as AllInOneIMECore's own `isBoolean`).
    var isBoolean: Bool {
        self === NSNumber(value: true) || self === NSNumber(value: false)
    }
}
