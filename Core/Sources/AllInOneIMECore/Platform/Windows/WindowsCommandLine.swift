#if os(Windows)
import Foundation

/// A Windows program gets one command line, not a list of arguments: each program splits it itself, most with the C
/// runtime's rules (`CommandLineToArgvW`'s), cmd.exe with its own. This writes the line so that the program reads back
/// exactly the arguments given, as Rust's standard library does (`std::process::Command` on Windows).
enum WindowsCommandLine {
    /// `argv` (the program first) as one command line the C runtime splits back into `argv`: the program in quotes, as
    /// written (a file name has no `"`); every argument in quotes too, its `"` escaped with a backslash and the
    /// backslashes before a `"` (its own or the closing one) doubled. In quotes even without a space (Rust's
    /// `force_quotes`): a program built on MSYS2's or Cygwin's runtime (Git Bash's bash and tools) reads its line as a
    /// shell would, and expands `*`, `?`, `[…]`, `{a,b}`, `~`, `@file` and `'…'` in a word that isn't in quotes.
    static func make(_ argv: [String]) throws -> String {
        guard let program = argv.first else { return "" }
        guard !program.contains("\""), !program.contains("\0") else { throw WindowsLaunchError.invalidArgument("a `\"` in the program's name") }
        var line = "\"" + program + "\""
        for argument in argv.dropFirst() {
            line += " "
            line += try quoted(argument)
        }
        return line
    }

    /// One argument, in quotes, as the C runtime reads it back.
    static func quoted(_ argument: String) throws -> String {
        guard !argument.contains("\0") else { throw WindowsLaunchError.invalidArgument("a NUL character in an argument") }
        var out = "\""
        var backslashes = 0
        for scalar in argument.unicodeScalars {
            if scalar == "\\" {
                backslashes += 1
            } else {
                // n backslashes before a `"` become 2n + 1: the `"` escaped.
                if scalar == "\"" { out += String(repeating: "\\", count: backslashes + 1) }
                backslashes = 0
            }
            out.unicodeScalars.append(scalar)
        }
        // n backslashes before the closing `"` become 2n.
        return out + String(repeating: "\\", count: backslashes) + "\""
    }

    /// The command line that runs the batch file `script` (.bat, .cmd) with `arguments` through cmd.exe, which a batch
    /// file always runs in, and which reads the line with its own rules: `&`, `|`, `<`, `>`, `^` and `%VAR%` there mean
    /// something even in an argument. Written as Rust does since it was found to be unsafe that way (BatBadBut,
    /// CVE-2024-24576): `cmd.exe /e:ON /v:OFF /d /c ""script" args"`, without AutoRun commands or delayed expansion
    /// (`!VAR!`), each argument with anything but letters, digits and `#$*+-./:?@\_` in quotes, its `"` doubled, the
    /// backslashes before a `"` doubled, and each `%` written `%%cd:~,%` (an empty piece of %cd%: nothing a variable's
    /// name can be read from). An argument with a line break (or a NUL) is refused: cmd.exe would end the command there.
    /// So is a script whose path has a `%`, which cmd.exe would expand in it too (C:\Users\me\%TEMP%\x.bat).
    static func batch(script: String, arguments: [String]) throws -> String {
        guard !script.contains("\""), !script.hasSuffix("\\"), !script.contains("\0") else {
            throw WindowsLaunchError.invalidArgument("a batch file's name with a `\"` or ending in `\\`")
        }
        guard !script.contains("%") else { throw WindowsLaunchError.invalidArgument("a batch file's path with a `%`") }
        var line = "cmd.exe /e:ON /v:OFF /d /c \"\"" + script + "\""
        for argument in arguments {
            guard !argument.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\r\n" || $0 == "\0" }) else {
                throw WindowsLaunchError.invalidArgument("a line break in an argument to a batch file")
            }
            line += " " + batchArgument(argument)
        }
        return line + "\""
    }

    /// The characters an argument to a batch file may have outside quotes, besides ASCII letters and digits.
    private static let plain = Set(#"#$*+-./:?@\_"#.unicodeScalars)

    private static func batchArgument(_ argument: String) -> String {
        // Empty, or ending in a backslash (which would escape the closing quote of a "%~1" in the script): quoted.
        var quote = argument.isEmpty || argument.hasSuffix("\\")
        for scalar in argument.unicodeScalars {
            let letterOrDigit = ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
            if scalar.isASCII && !letterOrDigit && !plain.contains(scalar) || scalar.properties.generalCategory == .control { quote = true }
        }
        var out = quote ? "\"" : ""
        var backslashes = 0
        for scalar in argument.unicodeScalars {
            if scalar == "\\" {
                backslashes += 1
            } else {
                if scalar == "\"" {
                    out += String(repeating: "\\", count: backslashes) + "\""  // 2n backslashes, the `"` doubled
                } else if scalar == "%" {
                    out += "%%cd:~,"
                }
                backslashes = 0
            }
            out.unicodeScalars.append(scalar)
        }
        if quote { out += String(repeating: "\\", count: backslashes) + "\"" }
        return out
    }
}
#endif
