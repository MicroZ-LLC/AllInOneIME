import Foundation

/// A JavaScript engine, for plugins (`PluginScript`) and `@js` (`InlineCode`): JavaScriptCore on Apple platforms
/// (`JavaScriptCoreEngine`), QuickJS-ng on Windows, Linux and Android (`QuickJSEngine`, in AllInOneIMEQuickJS), or none
/// (`UnsupportedScriptEngine`). Its own module, below the core, so that an engine outside the core can be the core's
/// default; the core re-exports it.
public protocol ScriptEngine: Sendable {
    /// A fresh context, with nothing but the language; nil when there is no JavaScript here.
    func makeContext() -> (any ScriptEngineContext)?
}

/// One JavaScript context and its globals, used from one thread at a time.
public protocol ScriptEngineContext: AnyObject {
    /// What the last script or call threw (nil: nothing has). A later script that doesn't throw leaves it as it is.
    var exception: (any ScriptValue)? { get }
    /// Runs `source`: its completion value (undefined after a throw: see `exception`).
    @discardableResult func evaluate(_ source: String) -> (any ScriptValue)?
    /// Whether `source` is a valid script (nothing runs).
    func checkSyntax(_ source: String) -> Bool
    /// A global variable (undefined when there's none).
    func global(_ name: String) -> (any ScriptValue)?
    /// Sets a global variable to `value`: a `ScriptValue`, or text, a number, a Bool, an array or a dictionary of them.
    func setGlobal(_ name: String, _ value: Any)
    /// A native function as a script value: `body` gets the arguments it was called with and returns its result (as
    /// for `setGlobal`; nil: undefined).
    func function(_ body: @escaping ([any ScriptValue]) -> Any?) -> any ScriptValue
    /// Stops whatever runs here once it has run `seconds` (it throws). False when the engine can't: then the script
    /// has to run where it can be stopped from outside (a child process, as on the Mac). True is best effort, not a
    /// promise: an engine stops a script where it checks the clock, and some of its built-in functions run long without
    /// checking (QuickJS-ng's `Array.prototype.reverse.call({length: 2 ** 53 - 1})`, say). Plugins and `@js` run in a
    /// child process all the same, which the runner kills (`PluginHost`, `--run-js`).
    func limitTime(to seconds: Double) -> Bool
}

/// A value of a `ScriptEngineContext`.
public protocol ScriptValue: AnyObject {
    var isUndefined: Bool { get }
    var isObject: Bool { get }
    var isString: Bool { get }
    var isNumber: Bool { get }
    /// As JavaScript converts it to a Boolean.
    var boolValue: Bool { get }
    /// The number (nil unless it is one).
    var numberValue: Double? { get }
    /// As JavaScript's `String(value)` has it.
    func toString() -> String?
    /// An array's items, converted (text, numbers, arrays, dictionaries); nil for anything else.
    func toArray() -> [Any]?
    /// An object's properties, converted; nil for anything else.
    func toDictionary() -> [String: Any]?
    /// One of its properties (undefined when it has none).
    func property(_ name: String) -> (any ScriptValue)?
    /// Calls it with `arguments` (as for `ScriptEngineContext.setGlobal`): the result (undefined after a throw: see the
    /// context's `exception`).
    func call(_ arguments: [Any]) -> (any ScriptValue)?
}

/// No JavaScript on this platform: plugin scripts and `@js` say so.
public struct UnsupportedScriptEngine: ScriptEngine {
    public init() {}
    public func makeContext() -> (any ScriptEngineContext)? { nil }
}
