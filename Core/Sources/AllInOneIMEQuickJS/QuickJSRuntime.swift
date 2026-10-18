import Foundation
import AllInOneIMEScriptEngine
internal import CQuickJS

/// A QuickJS runtime and its one context. The `QuickJSContext` and each of its values hold it, so it is freed after the
/// last of them (QuickJS's runtime must outlive every value of it). Used from one thread at a time, except its `clock`,
/// which QuickJS's interrupt handler reads as scripts run.
final class QuickJSRuntime {
    let rt: OpaquePointer
    let ctx: OpaquePointer
    /// The class of the objects that hold a native function's Swift body (`function`), released when QuickJS frees them.
    private var functionClass: JSClassID = 0
    /// The last exception, held raw: as a `QuickJSValue` it would hold the runtime.
    private var thrown: JSValue?
    /// How deep in calls into QuickJS this is: a native function's body may call back in.
    private var depth = 0
    /// How far down this thread's stack Swift's own conversions go (`ThreadStack.floor`), from the outermost call.
    private(set) var stackFloor: UInt = 0
    /// When scripts stop.
    let clock = ScriptClock()
    /// What it may allocate. Freed after QuickJS's runtime (stored properties go after `deinit`), which frees through it.
    private let memory: MemoryBudget

    /// The file name QuickJS's messages and stacks give the scripts: one of ours, since QuickJS calls the text it parses
    /// for `JSON.parse` and `eval` "<input>", and only the scripts' own places in a stack are their lines (`addLine`).
    static let fileName = "<allinoneime>"

    init?(memoryLimit: Int) {
        let memory = MemoryBudget(limit: memoryLimit)
        guard let rt = memory.newRuntime() else { return nil }
        guard let ctx = JS_NewContext(rt) else {
            JS_FreeRuntime(rt)
            return nil
        }
        self.rt = rt
        self.ctx = ctx
        self.memory = memory
        JS_SetContextOpaque(ctx, Unmanaged.passUnretained(self).toOpaque())
        JS_SetInterruptHandler(rt, { _, opaque in
            guard let opaque else { return 0 }
            return Unmanaged<ScriptClock>.fromOpaque(opaque).takeUnretainedValue().isUp ? 1 : 0
        }, Unmanaged.passUnretained(clock).toOpaque())
        // A body is released with the object that holds it (its finalizer), whenever QuickJS frees that: when the
        // function is collected, or at the latest with the runtime.
        JS_NewClassID(rt, &functionClass)
        var definition = JSClassDef(class_name: nil, finalizer: { _, holder in
            var id: JSClassID = 0
            if let body = JS_GetAnyOpaque(holder, &id) { Unmanaged<NativeFunction>.fromOpaque(body).release() }
        }, gc_mark: nil, call: nil, exotic: nil)
        "AllInOneIMENativeFunction".withCString { name in
            definition.class_name = name
            _ = JS_NewClass(rt, functionClass, &definition)
        }
    }

    deinit {
        if let thrown { JS_FreeValue(ctx, thrown) }
        JS_FreeContext(ctx)
        JS_FreeRuntime(rt)
    }

    // MARK: - Running

    /// Runs `body`, which calls into QuickJS. From the outermost call: first the stack's limits, QuickJS's and Swift's,
    /// for this thread (a context may move between threads from one call to the next), and after it the promise jobs it
    /// queued, as JavaScriptCore runs its microtasks before it returns (none once the clock is up: jobs that queue jobs
    /// don't end).
    func enter<T>(_ body: () -> T) -> T {
        if depth == 0 {
            let stack = ThreadStack.current()
            JS_SetMaxStackSize(rt, stack.scriptLimit)
            JS_UpdateStackTop(rt)
            stackFloor = stack.floor
            memory.reset()
        }
        depth += 1
        defer { depth -= 1 }
        let result = body()
        if depth == 1 {
            var context: OpaquePointer?
            while !clock.isUp && JS_IsJobPending(rt) {
                if JS_ExecutePendingJob(rt, &context) < 0 { takeException() }
            }
        }
        return result
    }

    /// Runs a script (`evaluate`, a function's `call`): what it gives, as `wrap` has it. Once the clock is up none runs,
    /// and it throws as QuickJS's interrupt handler makes a script throw (which a short one could end before QuickJS asks).
    func run(_ script: () -> JSValue) -> QuickJSValue {
        enter {
            guard !clock.isUp else {
                throwError(.internal, "interrupted")
                return QuickJSValue(self, QJS_Undefined())
            }
            return wrap(script())
        }
    }

    var exception: QuickJSValue? {
        thrown.map { QuickJSValue(self, JS_DupValue(ctx, $0)) }
    }

    /// Takes what was thrown as the exception, as JavaScriptCore's handler does.
    func takeException() {
        var error = JS_GetException(ctx)
        // Nothing thrown, only failed: out of memory, with none left for the error (`MemoryBudget`'s reserve used up).
        // It is made now, the memory of what failed freed (null should that fail too, as QuickJS throws it then).
        if JS_IsUninitialized(error) {
            _ = JS_ThrowOutOfMemory(ctx)
            error = JS_GetException(ctx)
            if JS_IsUninitialized(error) { error = QJS_Null() }
        }
        addLine(to: error)
        if let thrown { JS_FreeValue(ctx, thrown) }
        thrown = error
    }

    /// Drops what was thrown, for what fails in passing (a getter while converting, as JavaScriptCore ignores it).
    func dropException() {
        JS_FreeValue(ctx, JS_GetException(ctx))
    }

    /// `value` as a `QuickJSValue` (it takes it over); undefined after a throw, as JavaScriptCore returns it.
    func wrap(_ value: JSValue) -> QuickJSValue {
        if JS_IsException(value) {
            takeException()
            return QuickJSValue(self, QJS_Undefined())
        }
        return QuickJSValue(self, value)
    }

    /// The line an error was made on, as JavaScriptCore gives it (`line`), from the first place in its stack that is in
    /// a script of ours ("    at f (<allinoneime>:3:7)", "    at <allinoneime>:1:4" for a syntax error), not in what
    /// `JSON.parse` or `eval` parsed ("    at <input>:4:1"): the line of the call, as JavaScriptCore has it. `InlineCode`
    /// shows it.
    private func addLine(to error: JSValue) {
        guard JS_IsError(error), JS_IsObject(error) else { return }
        let has = JS_GetPropertyStr(ctx, error, "line")
        defer { JS_FreeValue(ctx, has) }
        guard JS_IsUndefined(has) else {
            if JS_IsException(has) { dropException() }
            return
        }
        let stack = JS_GetPropertyStr(ctx, error, "stack")
        defer { JS_FreeValue(ctx, stack) }
        guard JS_IsString(stack), let text = string(stack) else {
            if JS_IsException(stack) { dropException() }
            return
        }
        for frame in text.split(whereSeparator: \.isNewline) {
            guard let file = frame.range(of: Self.fileName + ":", options: .backwards) else { continue }
            let rest = frame[file.upperBound...]
            let place = rest.hasSuffix(")") ? rest.dropLast() : rest
            let parts = place.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, Int(parts[1]) != nil, let line = Int32(parts[0]) else { continue }
            JS_DefinePropertyValueStr(ctx, error, "line", JS_NewInt32(ctx, line), Int32(JS_PROP_CONFIGURABLE | JS_PROP_WRITABLE))
            return
        }
    }

    // MARK: - The context

    func evaluate(_ source: String) -> QuickJSValue {
        run { eval(source, flags: Int32(JS_EVAL_TYPE_GLOBAL)) }
    }

    func checkSyntax(_ source: String) -> Bool {
        enter {
            let compiled = eval(source, flags: Int32(JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY))
            // Not the context's exception: JavaScriptCore's syntax check doesn't report one either.
            if JS_IsException(compiled) {
                dropException()
                return false
            }
            JS_FreeValue(ctx, compiled)
            return true
        }
    }

    /// QuickJS's parser wants the text to end in a NUL, past the length it is given.
    private func eval(_ source: String, flags: Int32) -> JSValue {
        source.utf8CString.withUnsafeBufferPointer { code in
            JS_Eval(ctx, code.baseAddress, code.count - 1, Self.fileName, flags)
        }
    }

    func global(_ name: String) -> QuickJSValue {
        enter {
            let global = JS_GetGlobalObject(ctx)
            defer { JS_FreeValue(ctx, global) }
            return wrap(JS_GetPropertyStr(ctx, global, name))
        }
    }

    func setGlobal(_ name: String, _ value: Any) {
        enter {
            let global = JS_GetGlobalObject(ctx)
            defer { JS_FreeValue(ctx, global) }
            if JS_SetPropertyStr(ctx, global, name, makeValue(value)) < 0 { takeException() }
        }
    }

    func function(_ body: @escaping ([any ScriptValue]) -> Any?) -> QuickJSValue {
        enter {
            var holder = JS_NewObjectClass(ctx, functionClass)
            guard !JS_IsException(holder) else { return wrap(holder) }
            defer { JS_FreeValue(ctx, holder) }  // the function holds it now
            JS_SetOpaque(holder, Unmanaged.passRetained(NativeFunction(body)).toOpaque())
            return wrap(JS_NewCFunctionData(ctx, { ctx, _, count, arguments, _, data in
                guard let ctx, let data, let me = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
                var id: JSClassID = 0
                guard let body = JS_GetAnyOpaque(data[0], &id) else { return QJS_Undefined() }
                let runtime = Unmanaged<QuickJSRuntime>.fromOpaque(me).takeUnretainedValue()
                let function = Unmanaged<NativeFunction>.fromOpaque(body).takeUnretainedValue()
                let values = (0..<Int(count)).map { QuickJSValue(runtime, JS_DupValue(ctx, arguments![$0])) }
                return runtime.enter { runtime.makeValue(function.body(values)) }
            }, 0, 0, 1, &holder))
        }
    }
}

/// When a runtime's scripts stop: past `limit`'s deadline, or once `interrupt`ed. Set from any thread; QuickJS's
/// interrupt handler reads it as scripts run.
final class ScriptClock: @unchecked Sendable {
    private let lock = NSLock()
    /// `DispatchTime`'s nanoseconds; nil: no limit.
    private var deadline: UInt64?
    private var interrupted = false

    var isUp: Bool {
        lock.withLock {
            if interrupted { return true }
            guard let deadline else { return false }
            return DispatchTime.now().uptimeNanoseconds >= deadline
        }
    }

    /// `seconds` from now (none: now; `.infinity`: no limit).
    func limit(to seconds: Double) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            if seconds.isNaN || seconds <= 0 {
                deadline = now
            } else if seconds * 1e9 >= Double(UInt64.max - now) {
                deadline = nil
            } else {
                deadline = now + UInt64(seconds * 1e9)
            }
        }
    }

    func interrupt() {
        lock.withLock { interrupted = true }
    }
}

/// A native function's Swift body, held by a QuickJS object of `QuickJSRuntime.functionClass`.
final class NativeFunction {
    let body: ([any ScriptValue]) -> Any?

    init(_ body: @escaping ([any ScriptValue]) -> Any?) { self.body = body }
}
