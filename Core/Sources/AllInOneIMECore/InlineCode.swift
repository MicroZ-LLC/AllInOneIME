import Foundation

/// `@js`: a line of code, run REPL style. When the code ends with an expression, its value is the result
/// (text as it is, anything else written as a literal: `[1, "a"]`); before it comes what the code printed.
/// Code that ends with a statement gives what it printed. An error (an exception, a failed exit) is shown
/// as one line: its first. (Python, `@py`, is one of Settings' examples: `CommandExamples.python`.)
///
/// The code always runs in a child process through `CommandRunner` (timeout, output limit, Esc, the
/// user's shell PATH, the home folder as the working directory), never in the input method: a script
/// that doesn't end couldn't be stopped there. It runs in this app's own executable (`runJavaScriptHost`),
/// in the platform's JavaScript (`Platform.scripts`: JavaScriptCore, which is part of macOS; QuickJS-ng
/// elsewhere), which has nothing but the language (no files, programs, network or timers).
///
/// The code is what the user typed or pasted: it never contains the output of other commands
/// (`Command.isCode`), let alone a model's.
public enum InlineCode {
    /// The option that makes this app's executable the child process `@js` code runs in.
    public static let javaScriptHostOption = "--run-js"

    /// The program `command` runs, as a `run` definition for `CommandRunner` (the code on standard
    /// input, full-width punctuation as ASCII); nil for a command that isn't code.
    public static func definition(for command: Command,
                                  executable: String = Bundle.main.executablePath ?? CommandLine.arguments[0]) -> CustomCommand? {
        guard command == .js else { return nil }
        return CustomCommand(name: command.name, type: .run, argv: [executable, javaScriptHostOption], stdin: CustomCommand.placeholder,
                             ascii: true, timeoutSeconds: CustomCommand.defaultTimeout)
    }

    // MARK: - JavaScript

    /// Defines `console` (log, info, debug, dir: printed; warn, error, trace: warnings) over the native
    /// `write(text, isWarning)` it is called with, and returns `show` (a value as inserted: text and
    /// numbers as they are, anything else as a literal like the browser console's) and `describe` (a
    /// thrown value as text).
    static let javaScriptPrelude = #"""
        (function (write) {
          function key(name) {
            return /^[A-Za-z_$][\w$]*$/.test(name) ? name : JSON.stringify(name);
          }
          function literal(value, depth, seen) {
            switch (typeof value) {
              case "string": return JSON.stringify(value);
              case "bigint": return value + "n";
              case "number": return Object.is(value, -0) ? "-0" : String(value);
              case "symbol": return value.toString();
              case "function": return "[Function" + (value.name ? ": " + value.name : "") + "]";
              case "object": break;
              default: return String(value);
            }
            if (value === null) return "null";
            if (seen.indexOf(value) >= 0) return "[Circular]";
            if (value instanceof Date) return isNaN(value) ? "Invalid Date" : value.toISOString();
            if (value instanceof RegExp || value instanceof Error) return String(value);
            if (depth > 4) return Array.isArray(value) ? "[Array]" : "[Object]";
            var inner = function (item) { return literal(item, depth + 1, seen.concat([value])); };
            if (Array.isArray(value)) return "[" + Array.from(value, inner).join(", ") + "]";
            if (value instanceof Map) {
              return "Map {" + Array.from(value, function (entry) {
                return inner(entry[0]) + " => " + inner(entry[1]);
              }).join(", ") + "}";
            }
            if (value instanceof Set) return "Set {" + Array.from(value, inner).join(", ") + "}";
            if (ArrayBuffer.isView(value) && "length" in value) {
              return value.constructor.name + " [" + Array.from(value, inner).join(", ") + "]";
            }
            var prototype = Object.getPrototypeOf(value);
            var name = value[Symbol.toStringTag] || (prototype === Object.prototype || prototype === null ? ""
              : (prototype.constructor && prototype.constructor.name) || "");
            var body = "{" + Object.keys(value).map(function (k) { return key(k) + ": " + inner(value[k]); }).join(", ") + "}";
            return name ? name + " " + body : body;
          }
          function show(value) {
            return typeof value === "string" ? value : typeof value === "bigint" ? String(value) : literal(value, 0, []);
          }
          function line(args) { return Array.prototype.map.call(args, show).join(" "); }
          var print = function () { write(line(arguments), false); };
          var warn = function () { write(line(arguments), true); };
          globalThis.console = { log: print, info: print, debug: print, dir: print, warn: warn, error: warn, trace: warn };
          return {
            show: show,
            describe: function (error) {
              try { return error instanceof Error ? String(error) : show(error); } catch (_) { return "error"; }
            }
          };
        })
        """#

    /// Runs `code` REPL style in a fresh JavaScript context (`Platform.scripts`): `console.log` lines go to `print` as
    /// they are logged, then the value of the last statement (the script's completion value, as in the browser
    /// console; none for `undefined`); `console.warn` and `console.error` lines go to `warn`. Code in
    /// braces is an object literal when it can be one (`{a: 1}`), as in Node's REPL. Throws the error as
    /// one line. Only for the child process (`runJavaScriptHost`) and tests: a script that never ends
    /// can't be stopped in the process it runs in.
    static func runJavaScript(_ code: String, print: @escaping (String) -> Void, warn: @escaping (String) -> Void,
                              engine: any ScriptEngine = Platform.current.scripts) throws {
        guard let context = engine.makeContext() else { throw InlineCodeError("JavaScript is not available") }
        let write = context.function { arguments in
            let text = arguments.first?.toString() ?? "undefined"
            arguments.count > 1 && arguments[1].boolValue ? warn(text) : print(text)
            return nil
        }
        guard let helpers = context.evaluate(javaScriptPrelude)?.call([write]), context.exception == nil,
              let show = helpers.property("show"), let describe = helpers.property("describe")
        else { throw InlineCodeError("JavaScript is not available") }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let asObject = trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && context.checkSyntax("(" + trimmed + ")")
        let value = context.evaluate(asObject ? "(" + trimmed + ")" : code)
        if context.exception == nil, let value, !value.isUndefined {
            let text = show.call([value])
            if context.exception == nil, let text = text?.toString() { print(text) }
        }
        guard let exception = context.exception else { return }
        var message = describe.call([exception])?.toString() ?? "error"
        message = message.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if message.isEmpty { message = "error" }
        if trimmed.contains(where: \.isNewline), let line = exception.property("line")?.numberValue {
            // As JavaScript makes it a 32-bit integer (anything thrown may carry a `line`, NaN too).
            message += " (line \(line.isFinite ? Int32(truncatingIfNeeded: Int64(line.truncatingRemainder(dividingBy: 4_294_967_296))) : 0))"
        }
        throw InlineCodeError(message)
    }

    /// `runJavaScript`, with what it prints collected: one line each.
    static func evaluateJavaScript(_ code: String) throws -> String {
        var lines: [String] = []
        try runJavaScript(code, print: { lines.append($0) }, warn: { _ in })
        return lines.joined(separator: "\n")
    }

    /// `AllInOneIME --run-js`: the child process `@js` code runs in. The code comes on standard input; what
    /// it prints goes to standard output as it comes (so the runner's output limit applies), warnings and
    /// an error message to standard error (exit status 1).
    public static func runJavaScriptHost() -> Int32 {
        func write(_ text: String, to handle: FileHandle) { handle.write(Data((text + "\n").utf8)) }
        let code = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        do {
            try runJavaScript(code, print: { write($0, to: .standardOutput) }, warn: { write($0, to: .standardError) })
            return 0
        } catch {
            write((error as? LocalizedError)?.errorDescription ?? "\(error)", to: .standardError)
            return 1
        }
    }
}

/// Code that failed, with its error as one line ("ReferenceError: Can't find variable: x").
public struct InlineCodeError: Error, LocalizedError, Equatable, Sendable {
    public var message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}
