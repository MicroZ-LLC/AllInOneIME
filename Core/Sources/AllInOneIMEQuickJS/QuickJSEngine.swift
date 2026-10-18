import Foundation
import AllInOneIMEScriptEngine

/// QuickJS-ng (Sources/CQuickJS), the JavaScript of the systems without JavaScriptCore: Windows, Linux and Android.
/// Like JavaScriptCore, the language and nothing else (no files, programs, network or timers), with the values
/// JavaScriptCore gives Swift (`QuickJSValue`). Unlike it, a script can be stopped where it runs (`limitTime`,
/// `QuickJSContext.interrupter`): each context is a runtime of its own, with its clock, its memory (`MemoryBudget`),
/// and a stack limit that fits the thread it runs on (`ThreadStack`).
public struct QuickJSEngine: ScriptEngine {
    /// The most a context's scripts may allocate, in bytes; past it what allocates throws ("out of memory").
    public var memoryLimit: Int

    /// 128 MB: a plugin's answers are 1 MB at most (`URLSessionFetcher.maxBytes`), and `@js` is a line of code.
    public static let defaultMemoryLimit = 128 << 20

    public init(memoryLimit: Int = QuickJSEngine.defaultMemoryLimit) {
        self.memoryLimit = memoryLimit
    }

    public func makeContext() -> (any ScriptEngineContext)? {
        QuickJSContext(memoryLimit: memoryLimit)
    }
}

/// A QuickJS context, alone in its runtime (`QuickJSRuntime`), which it and its values share: the last of them frees it.
public final class QuickJSContext: ScriptEngineContext {
    let runtime: QuickJSRuntime

    init?(memoryLimit: Int) {
        guard let runtime = QuickJSRuntime(memoryLimit: memoryLimit) else { return nil }
        self.runtime = runtime
    }

    public var exception: (any ScriptValue)? { runtime.exception }

    @discardableResult
    public func evaluate(_ source: String) -> (any ScriptValue)? {
        runtime.evaluate(source)
    }

    public func checkSyntax(_ source: String) -> Bool {
        runtime.checkSyntax(source)
    }

    public func global(_ name: String) -> (any ScriptValue)? {
        runtime.global(name)
    }

    public func setGlobal(_ name: String, _ value: Any) {
        runtime.setGlobal(name, value)
    }

    public func function(_ body: @escaping ([any ScriptValue]) -> Any?) -> any ScriptValue {
        runtime.function(body)
    }

    /// From now on, `seconds` more for whatever runs here: past them a running script throws ("InternalError:
    /// interrupted", which it can't catch), and so does any script or call after it. `.infinity` lifts the limit.
    public func limitTime(to seconds: Double) -> Bool {
        runtime.clock.limit(to: seconds)
        return true
    }

    /// Stops what runs here: it throws as past `limitTime`'s, and so does any script or call after it.
    public func interrupt() {
        runtime.clock.interrupt()
    }

    /// `interrupt`, for another thread to call while a script runs here (Esc, say): the context itself stays on its own.
    public var interrupter: @Sendable () -> Void {
        let clock = runtime.clock
        return { clock.interrupt() }
    }
}
