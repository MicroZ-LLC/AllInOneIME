import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMEQuickJS

/// What QuickJS-ng has that JavaScriptCore doesn't give the core (`QuickJSEngine`): scripts stopped where they run, by the
/// clock (`limitTime`) or from another thread (`interrupter`), limits on memory and depth that throw instead of crashing,
/// and contexts that free what they hold.
struct QuickJSEngineTests {
    static let deepRecursion = "(function down(n) { return down(n + 1) + 1 })(0)"
    static let stackOverflow = "RangeError: Maximum call stack size exceeded"

    func context(memoryLimit: Int = QuickJSEngine.defaultMemoryLimit) throws -> QuickJSContext {
        try #require(QuickJSEngine(memoryLimit: memoryLimit).makeContext() as? QuickJSContext)
    }

    // MARK: - Time

    @Test func aTimeLimitStopsALoopThatCantCatchIt() throws {
        let context = try context()
        #expect(context.limitTime(to: 0.2))
        let start = Date()
        let value = context.evaluate("var n = 0; try { for (;;) n++ } catch (e) { 'caught' } finally { var after = 1 }")
        let took = Date().timeIntervalSince(start)
        #expect(value?.isUndefined == true && context.exception?.toString() == "InternalError: interrupted")
        #expect(took >= 0.15 && took < 5, "\(took) s")
        #expect((context.global("n")?.numberValue ?? 0) > 0 && context.global("after")?.isUndefined == true)
        // Past it nothing runs, however short (QuickJS asks its handler only every so many steps), until it's lifted.
        context.evaluate("throw new Error('other')")
        #expect(context.evaluate("1 + 1")?.isUndefined == true && context.exception?.toString() == "InternalError: interrupted")
        #expect(context.limitTime(to: .infinity) && context.evaluate("1 + 1")?.numberValue == 2)
        // None, or less: at once.
        #expect(context.limitTime(to: 0) && context.evaluate("2")?.isUndefined == true)
        #expect(context.limitTime(to: -.infinity) && context.evaluate("3")?.isUndefined == true)
        #expect(context.limitTime(to: .nan) && context.evaluate("4")?.isUndefined == true)
    }

    @Test func aTimeLimitStopsACallAndWhatItCalls() throws {
        // As PluginScript calls `run`: the function, and the native functions it calls in its loop.
        let context = try context()
        var calls = 0
        context.setGlobal("native", context.function { _ in
            calls += 1
            return "spun"
        })
        let run = try #require(context.evaluate("(function () { for (;;) native() })"))
        _ = context.limitTime(to: 0.1)
        #expect(run.call([])?.isUndefined == true && context.exception?.toString() == "InternalError: interrupted")
        #expect(calls > 0)
        // Its promise jobs too, those that queue more of themselves.
        let jobs = try self.context()
        _ = jobs.limitTime(to: 0.1)
        jobs.evaluate("var count = 0; (function again() { count++; Promise.resolve().then(again) })()")
        #expect((jobs.global("count")?.numberValue ?? 0) > 1)
    }

    @Test func anotherThreadStopsAScript() throws {
        let context = try context()
        let stop = context.interrupter
        _ = context.limitTime(to: 30)  // should the interrupter fail, the test fails instead of hanging
        let start = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { stop() }
        context.evaluate("for (;;) {}")
        let took = Date().timeIntervalSince(start)
        #expect(context.exception?.toString() == "InternalError: interrupted" && took < 10, "\(took) s")
        // And whatever runs after it, whatever the clock says.
        #expect(context.limitTime(to: .infinity) && context.evaluate("'after'")?.isUndefined == true)
        #expect(context.global("Math")?.isObject == true)  // its values can still be read
    }

    @Test func aScriptStopsItself() throws {
        let context = try context()
        context.setGlobal("stop", context.function { [unowned context] _ in
            context.interrupt()
            return nil
        })
        context.evaluate("stop(); for (;;) {}")
        #expect(context.exception?.toString() == "InternalError: interrupted")
    }

    // MARK: - Memory and depth

    @Test func aMemoryLimit() throws {
        #expect(QuickJSEngine().memoryLimit == 128 << 20 && QuickJSEngine.defaultMemoryLimit == 128 << 20)
        let context = try context(memoryLimit: 16 << 20)
        context.evaluate("(function () { const kept = []; for (;;) kept.push('x'.repeat(1024) + kept.length) })()")
        #expect(context.exception?.toString() == "InternalError: out of memory")
        // What it held is freed with it; the context goes on.
        #expect(context.evaluate("[1, 2, 3].map(x => x * 2).join()")?.toString() == "2,4,6")
        // One allocation past it.
        context.evaluate("new ArrayBuffer(64 << 20)")
        #expect(context.exception?.toString() == "InternalError: out of memory")
        // A string too long for it, from Swift.
        context.setGlobal("long", String(repeating: "x", count: 32 << 20))
        #expect(context.exception?.toString() == "InternalError: out of memory")
        #expect(context.evaluate("typeof long")?.toString() == "undefined")
        // What a script keeps stays: the error is made all the same (QuickJS's own limit would throw null), and the
        // context runs nothing more, each script out of memory before it starts (plugins and @js run in a context each).
        context.evaluate("var kept = []; for (;;) kept.push('z'.repeat(1024) + kept.length)")
        #expect(context.exception?.toString() == "InternalError: out of memory")
        #expect(context.evaluate("'more'")?.isUndefined == true && context.exception?.toString() == "InternalError: out of memory")
        // Another context has its own.
        #expect(try self.context(memoryLimit: 16 << 20).evaluate("'y'.repeat(1 << 20).length")?.numberValue == 1_048_576)
    }

    @Test func deepRecursionThrowsInsteadOfCrashing() throws {
        let context = try context()
        context.evaluate(Self.deepRecursion)
        #expect(context.exception?.toString() == Self.stackOverflow)
        #expect(context.evaluate("'still here'")?.toString() == "still here")
        // Nested too deep for the parser or JSON.
        context.evaluate("JSON.parse('['.repeat(1e6))")
        #expect(context.exception?.property("name")?.toString().map(["RangeError", "SyntaxError"].contains) == true)
        context.evaluate("[".repeated(100_000))
        #expect(context.exception?.property("name")?.toString().map(["RangeError", "SyntaxError"].contains) == true)
        let deep = context.evaluate("let deep = []; for (let i = 0; i < 1e5; i++) deep = [deep]; deep")
        context.evaluate("JSON.stringify(deep)")
        #expect(context.exception?.toString() == Self.stackOverflow)
        // Swift converts it as far as it goes (256 levels, `QuickJSRuntime.maxDepth`), and the next level empty.
        var level = try #require(deep?.toArray())
        var depth = 1
        while let inner = level.first as? [Any] {
            level = inner
            depth += 1
        }
        #expect(depth == 257 && level.isEmpty)
    }

    /// How deep scripts and Swift's conversions go fits the thread the context is used on, one after the other: a
    /// secondary thread's 512 KB on Apple platforms, less, or 1 MB (Windows's).
    @Test func onThreadsWithLittleStack() throws {
        nonisolated(unsafe) let context = try context()
        nonisolated(unsafe) let deep = try #require(context.evaluate("let deep = []; for (let i = 0; i < 1e5; i++) deep = [deep]; deep"))
        for size in [512 << 10, 256 << 10, 1 << 20, 192 << 10] {
            let done = DispatchSemaphore(value: 0)
            let results = Locked(initialState: [String?]())
            let thread = Thread {
                context.evaluate(Self.deepRecursion)
                let recursion = context.exception?.toString()
                context.evaluate("JSON.stringify(deep)")
                let json = context.exception?.toString()
                // Converted as far as the stack allows: empty past it.
                var level = deep.toArray() ?? [], depth = 1
                while let inner = level.first as? [Any] {
                    level = inner
                    depth += 1
                }
                results.withLock { $0 = [recursion, json, context.evaluate("'ok'")?.toString(), "\(depth > 32 && depth <= 257)"] }
                done.signal()
            }
            thread.stackSize = size
            thread.start()
            done.wait()
            #expect(results.withLock { $0 } == [Self.stackOverflow, Self.stackOverflow, "ok", "true"], "a \(size >> 10) KB stack")
        }
    }

    // MARK: - Lifetime

    @Test func aContextFreesWhatItHolds() throws {
        final class Token: Sendable {}
        weak var held: Token?
        do {
            let token = Token()
            held = token
            let context = try context()
            context.setGlobal("f", context.function { _ in withExtendedLifetime(token) { nil } })
            context.evaluate("f(); var cycle = {}; cycle.self = cycle")
            #expect(held != nil)
        }
        // A native function's body goes with the context, and with the function when that is collected before.
        #expect(held == nil)
        let context = try context()
        do {
            let token = Token()
            held = token
            _ = context.function { _ in withExtendedLifetime(token) { nil } }
        }
        #expect(held == nil)
        // A value outlives its context: it holds what it needs of it.
        var kept: (any ScriptValue)?
        do { kept = try self.context().evaluate("({a: [1, 2]})") }
        #expect(kept?.toDictionary()?["a"] as? [Int] == [1, 2])
    }
}

/// The core's JavaScript tests (plugins, `@js`, `@stock`, `@xe`) again, on QuickJS-ng injected for the task
/// (`Platform.override`): on Apple platforms the suites themselves run on JavaScriptCore, the platform's. A JavaScript
/// test added to them is added here too.
struct OnQuickJSTests {
    static let platform: Platform = {
        var platform = Platform()
        platform.scripts = QuickJSEngine()
        return platform
    }()

    func onQuickJS(_ body: () throws -> Void) throws {
        try Platform.$override.withValue(Self.platform) {
            #expect(Platform.current.scripts is QuickJSEngine)
            try body()
        }
    }

    @Test func inlineCode() throws {
        let tests = InlineCodeTests()
        try onQuickJS {
            try tests.javaScriptIsREPLStyle()
            try tests.javaScriptHasNothingButTheLanguage()
            tests.javaScriptErrorsAreOneLine()
            tests.javaScriptErrorLinesAreTheCodes()
        }
    }

    @Test func plugins() throws {
        let tests = PluginTests()
        try onQuickJS {
            try tests.scriptsGetNothingButFetch()
            try tests.scriptsAreToldTheInterfaceLanguageAndNothingElse()
            try tests.stockQuotes()
        }
    }

    @Test func xe() throws {
        let tests = XEPluginTests()
        try onQuickJS {
            try tests.convertsWithTheDateOfTheRate()
            try tests.readsTheWaysPeopleWriteIt()
            try tests.oneCurrencyOrSeveral()
            try tests.errors()
            try tests.fallsBackToFrankfurter()
            try tests.insideASentence()
        }
    }
}

private extension String {
    func repeated(_ count: Int) -> String { String(repeating: self, count: count) }
}
