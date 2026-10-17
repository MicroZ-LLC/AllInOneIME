#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore

/// JavaScriptCore, part of macOS and iOS: the language and nothing else (no files, programs, network or timers).
public struct JavaScriptCoreEngine: ScriptEngine {
    public init() {}

    public func makeContext() -> (any ScriptEngineContext)? {
        JSContext().map(JavaScriptCoreContext.init)
    }
}

final class JavaScriptCoreContext: ScriptEngineContext {
    let context: JSContext
    private(set) var exception: (any ScriptValue)?

    init(_ context: JSContext) {
        self.context = context
        // Weak: the handler is the context's own, and would keep this alive along with it.
        context.exceptionHandler = { [weak self] _, exception in
            self?.exception = exception.map(JavaScriptCoreValue.init)
        }
    }

    @discardableResult
    func evaluate(_ source: String) -> (any ScriptValue)? {
        context.evaluateScript(source).map(JavaScriptCoreValue.init)
    }

    func checkSyntax(_ source: String) -> Bool {
        let script = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(script) }
        return JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, nil)
    }

    func global(_ name: String) -> (any ScriptValue)? {
        context.objectForKeyedSubscript(name).map(JavaScriptCoreValue.init)
    }

    func setGlobal(_ name: String, _ value: Any) {
        context.setObject(JavaScriptCoreValue.unwrapped(value), forKeyedSubscript: name as NSString)
    }

    func function(_ body: @escaping ([any ScriptValue]) -> Any?) -> any ScriptValue {
        // The context it's called in, and its arguments, are JavaScriptCore's to give: the block holds neither (the
        // context holds the block).
        let block: @convention(block) () -> JSValue? = {
            guard let context = JSContext.current() else { return nil }
            let arguments = (JSContext.currentArguments() as? [JSValue] ?? []).map(JavaScriptCoreValue.init)
            guard let result = body(arguments) else { return JSValue(undefinedIn: context) }
            return JSValue(object: JavaScriptCoreValue.unwrapped(result), in: context)
        }
        return JavaScriptCoreValue(JSValue(object: block, in: context))
    }

    /// JavaScriptCore has no public way to stop a script: on the Mac scripts run in a child process, stopped from outside.
    func limitTime(to seconds: Double) -> Bool { false }
}

final class JavaScriptCoreValue: ScriptValue {
    let value: JSValue

    init(_ value: JSValue) { self.value = value }

    /// `value` as JavaScriptCore takes it: a `ScriptValue` of this engine as its `JSValue`.
    static func unwrapped(_ value: Any) -> Any {
        (value as? JavaScriptCoreValue)?.value ?? value
    }

    var isUndefined: Bool { value.isUndefined }
    var isObject: Bool { value.isObject }
    var isString: Bool { value.isString }
    var isNumber: Bool { value.isNumber }
    var boolValue: Bool { value.toBool() }
    var numberValue: Double? { value.isNumber ? value.toDouble() : nil }
    func toString() -> String? { value.toString() }
    func toArray() -> [Any]? { value.toArray() }
    func toDictionary() -> [String: Any]? { value.toDictionary() as? [String: Any] }

    func property(_ name: String) -> (any ScriptValue)? {
        value.objectForKeyedSubscript(name).map(JavaScriptCoreValue.init)
    }

    func call(_ arguments: [Any]) -> (any ScriptValue)? {
        value.call(withArguments: arguments.map(Self.unwrapped)).map(JavaScriptCoreValue.init)
    }
}
#endif
