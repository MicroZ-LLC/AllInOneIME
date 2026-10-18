import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMEQuickJS

/// A JavaScript engine the tests run on, by name.
struct TestEngine: Sendable, CustomTestStringConvertible {
    let name: String
    let engine: any ScriptEngine

    var testDescription: String { name }

    /// The platform's own (JavaScriptCore on Apple platforms, QuickJS-ng elsewhere), and QuickJS-ng where it isn't that
    /// (injected: the core links it off Apple platforms only). The core mustn't tell their values apart.
    static let all: [TestEngine] = {
        let system = Platform.systemScripts
        var engines: [TestEngine] = []
        if !(system is QuickJSEngine), system.makeContext() != nil {
            engines.append(TestEngine(name: "\(type(of: system))", engine: system))
        }
        return engines + [TestEngine(name: "QuickJSEngine", engine: QuickJSEngine())]
    }()

    /// A fresh context.
    func context() throws -> any ScriptEngineContext {
        try #require(engine.makeContext())
    }
}

/// What the core sees of a JavaScript engine (`ScriptEngine`), the same with each (`TestEngine.all`): the values Swift and
/// a script give each other, how numbers print, what a script throws, syntax checks, globals, native functions, calls.
struct ScriptEngineTests {
    @Test(arguments: TestEngine.all) func swiftValuesAsAScriptSeesThem(_ engine: TestEngine) throws {
        let context = try engine.context()
        context.setGlobal("text", "你好")
        context.setGlobal("whole", 42)
        context.setGlobal("fraction", 2.5)
        context.setGlobal("flag", true)
        context.setGlobal("none", NSNull())
        context.setGlobal("list", [1, "a", false, NSNull()] as [Any])
        context.setGlobal("fields", ["k": "v"])
        context.setGlobal("nested", ["a": [["b": 1]]] as [String: Any])
        context.setGlobal("when", Date(timeIntervalSince1970: 1))
        let seen = context.evaluate("""
            JSON.stringify([text, whole, fraction, flag, none, list, fields, nested]) + " " +
              [typeof whole, typeof flag, Array.isArray(list), when instanceof Date, when.getTime()].join()
            """)
        #expect(seen?.toString() == #"["你好",42,2.5,true,null,[1,"a",false,null],{"k":"v"},{"a":[{"b":1}]}] number,boolean,true,true,1000"#)
        #expect(context.exception == nil)
    }

    @Test(arguments: TestEngine.all) func scriptValuesAsSwiftSeesThem(_ engine: TestEngine) throws {
        let context = try engine.context()
        let object = try #require(context.evaluate("""
            ({text: "x", whole: 3, fraction: 0.5, flag: false, none: null, missing: undefined,
              list: [1, "two", null, undefined, [true]], inner: {deep: "yes"}, when: new Date(1500)})
            """))
        #expect(object.isObject && !object.isString && !object.isNumber && !object.isUndefined)
        let fields = try #require(object.toDictionary())
        // Undefined is left out; null is NSNull, in an array undefined too.
        #expect(Set(fields.keys) == ["text", "whole", "fraction", "flag", "none", "list", "inner", "when"])
        #expect(fields["text"] as? String == "x" && fields["whole"] as? Int == 3 && fields["fraction"] as? Double == 0.5)
        #expect(fields["flag"] as? Bool == false && fields["none"] is NSNull)
        let list = try #require(fields["list"] as? [Any])
        #expect(list.count == 5 && list[0] as? Int == 1 && list[1] as? String == "two" && list[2] is NSNull && list[3] is NSNull)
        #expect((list[4] as? [Any])?.first as? Bool == true)
        #expect((fields["inner"] as? [String: Any])?["deep"] as? String == "yes")
        #expect((fields["when"] as? Date)?.timeIntervalSince1970 == 1.5)
        #expect(context.evaluate("[1, 'a', [true]]")?.toArray()?.count == 3)
        // Numbers print as JavaScript prints them, whole ones without a fraction: what PluginScript makes of a script's
        // values ("\(item)").
        let numbers = context.evaluate("[1, -3, 2.5, 0.1, 1e21, 123456789012]")?.toArray()?.map { "\($0)" }
        #expect(numbers == ["1", "-3", "2.5", "0.1", "1e+21", "123456789012"])
        #expect(context.exception == nil)
        // Not an object: none, and anything but null or undefined is a TypeError.
        #expect(context.evaluate("null")?.toArray() == nil && context.evaluate("undefined")?.toDictionary() == nil)
        let other = try engine.context()
        #expect(other.evaluate("3")?.toArray() == nil)
        #expect(other.exception?.toString()?.hasPrefix("TypeError") == true)
    }

    @Test(arguments: TestEngine.all) func numbersAndText(_ engine: TestEngine) throws {
        let context = try engine.context()
        func value(_ code: String) -> (any ScriptValue)? { context.evaluate(code) }
        #expect(value("0.1 + 0.2")?.toString() == "0.30000000000000004" && value("1 / 3")?.toString() == "0.3333333333333333")
        #expect(value("1e21")?.toString() == "1e+21" && value("2 ** 53")?.toString() == "9007199254740992")
        #expect(value("-0")?.toString() == "0" && value("-0")?.numberValue == 0)
        #expect(value("NaN")?.numberValue?.isNaN == true && value("-Infinity")?.numberValue == -.infinity)
        #expect(value("7")?.numberValue == 7 && value("7")?.isNumber == true)
        #expect(value("'7'")?.numberValue == nil && value("'7'")?.isString == true && value("'7'")?.isNumber == false)
        #expect(value("12345678901234567890n")?.isNumber == false)  // a BigInt isn't a number
        #expect(value("'a' + 1")?.toString() == "a1" && value("[1, [2, 3]]")?.toString() == "1,2,3")
        #expect(value("({})")?.toString() == "[object Object]" && value("null")?.toString() == "null")
        #expect(value("undefined")?.toString() == "undefined" && value("undefined")?.isUndefined == true)
        #expect(value("'𝄞 é 你'")?.toString() == "𝄞 é 你" && value("'a\\u0000b'")?.toString() == "a\u{0}b")
        // As JavaScript converts to a Boolean.
        let truthy = ["1", "'0'", "[]", "({})", "-1", "Infinity"], falsy = ["0", "''", "null", "undefined", "NaN", "-0"]
        #expect(truthy.allSatisfy { value($0)?.boolValue == true } && falsy.allSatisfy { value($0)?.boolValue == false })
        #expect(value("null")?.isObject == false && value("(function () {})")?.isObject == true)
        #expect(context.exception == nil)
    }

    @Test(arguments: TestEngine.all) func whatAScriptThrows(_ engine: TestEngine) throws {
        let context = try engine.context()
        #expect(context.exception == nil)
        #expect(context.evaluate("1;\nthrow new TypeError('bad')")?.isUndefined == true)
        let error = try #require(context.exception)
        #expect(error.toString() == "TypeError: bad" && error.property("message")?.toString() == "bad")
        #expect(error.property("name")?.toString() == "TypeError" && error.property("line")?.numberValue == 2)
        // A later script that doesn't throw leaves it as it is.
        #expect(context.evaluate("6 * 7")?.numberValue == 42 && context.exception?.toString() == "TypeError: bad")
        // Anything may be thrown.
        context.evaluate("throw 'oops'")
        #expect(context.exception?.isString == true && context.exception?.toString() == "oops")
        context.evaluate("throw {code: 7}")
        #expect(context.exception?.property("code")?.numberValue == 7)
        // The engine's own errors: a syntax error (on its line), a variable that isn't there.
        context.evaluate("1\n2\n3 +")
        #expect(context.exception?.property("name")?.toString() == "SyntaxError")
        #expect(context.exception?.property("line")?.numberValue == 3)
        context.evaluate("missing")
        #expect(context.exception?.property("name")?.toString() == "ReferenceError")
        // What JSON.parse and eval parse has lines of its own: the error's is the line of the call.
        context.evaluate("\n\nJSON.parse('[1,\\n2,\\n3,\\nx]')")
        #expect(context.exception?.property("name")?.toString() == "SyntaxError" && context.exception?.property("line")?.numberValue == 3)
        context.evaluate("\nJSON.parse('{')")
        #expect(context.exception?.property("line")?.numberValue == 2)
        context.evaluate("function f() {\n  return eval('1\\n2\\n3 +')\n}\n\nf()")
        #expect(context.exception?.property("name")?.toString() == "SyntaxError" && context.exception?.property("line")?.numberValue == 2)
        // What a function throws when it's called.
        let thrower = context.evaluate("(function (x) { throw new RangeError('no ' + x) })")
        #expect(thrower?.call(["way"])?.isUndefined == true && context.exception?.toString() == "RangeError: no way")
    }

    @Test(arguments: TestEngine.all) func syntaxChecksAndGlobals(_ engine: TestEngine) throws {
        let context = try engine.context()
        #expect(context.checkSyntax("var ran = true; function f(a) { return a }") && context.checkSyntax("({a: 1})"))
        #expect(!context.checkSyntax("1 +") && !context.checkSyntax("function ( {"))
        // Nothing runs, and a failed check isn't the context's exception.
        #expect(context.global("ran")?.isUndefined == true && context.global("f")?.isUndefined == true)
        #expect(context.exception == nil)
        context.setGlobal("n", 1)
        context.evaluate("var m = n + 1; let hidden = 3")
        #expect(context.global("m")?.numberValue == 2 && context.global("hidden")?.isUndefined == true)
        #expect(context.global("nothing")?.isUndefined == true && context.global("Math")?.isObject == true)
        // Contexts don't share their globals.
        #expect(try engine.context().global("m")?.isUndefined == true)
    }

    @Test(arguments: TestEngine.all) func nativeFunctionsAndCalls(_ engine: TestEngine) throws {
        let context = try engine.context()
        var calls: [[String]] = []
        let native = context.function { arguments in
            calls.append(arguments.map { $0.toString() ?? "?" })
            return ["count": arguments.count, "items": arguments.first?.toArray() ?? [],
                    "fields": arguments.last?.toDictionary() ?? [:]] as [String: Any]
        }
        context.setGlobal("native", native)
        context.setGlobal("nothing", context.function { _ in nil })
        let result = context.evaluate("var r = native(['a', 1], {k: 'v'}); [typeof native, r.count, r.items.join('|'), r.fields.k, typeof nothing()].join()")
        #expect(result?.toString() == "function,2,a|1,v,undefined")
        #expect(calls == [["a,1", "[object Object]"]])
        // Called from Swift, with Swift's values or the context's own.
        #expect(native.call([[3, 4]])?.property("count")?.numberValue == 1 && calls.last == ["3,4"])
        let describe = try #require(context.evaluate("(function (a, b, c) { return [typeof a, typeof b, Array.isArray(c), c[1].k].join() })"))
        #expect(describe.call(["x", 2, [true, ["k": "v"]] as [Any]])?.toString() == "string,number,true,v")
        let object = try #require(context.evaluate("({n: 5})"))
        #expect(context.evaluate("(function (o) { return o.n * 2 })")?.call([object])?.numberValue == 10)
        #expect(context.exception == nil)
        // Promise jobs run before the script that queued them returns.
        context.evaluate("var later = 'no'; Promise.resolve().then(() => { later = 'yes' })")
        #expect(context.global("later")?.toString() == "yes")
    }
}
