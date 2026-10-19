import AllInOneIMECLI
import AllInOneIMEEngineKit
import Foundation
#if os(Windows)
import WinSDK
#endif

// The core's command line on the core's own platform (`Platform()`: on Windows its Platform/Windows/ implementations,
// the Credential Manager for API keys, programs in job objects, the Recycle Bin). What else the shell brings (its
// environment) comes with the input method.
// `wire-replay` is the Windows shell's own: the wire protocol's goldens over the engine's pipe. So are the settings
// commands (`SettingsCommands`: set-provider, set-key, remove-key, set-input, show-config), while Windows has no
// settings window.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "wire-replay" {
    exit(WireReplay.main(Array(arguments.dropFirst())))
}
if let command = arguments.first, SettingsCommands.names.contains(command) {
    let io = SettingsCommands.IO(
        readKey: { readKey(prompt: "Paste the API key (it isn't shown), then Enter: ") },
        print: { print($0) },
        fail: { FileHandle.standardError.write(Data("allinoneime-cli: \($0)\n".utf8)) })
    exit(SettingsCommands.run(arguments, io: io))
}
await CLI.run()

/// The key from standard input: typed at a console with the echo off, after `prompt`; else all of what is piped in.
func readKey(prompt: String) -> String? {
    #if os(Windows)
    if let input = GetStdHandle(STD_INPUT_HANDLE), input != INVALID_HANDLE_VALUE {
        var mode: DWORD = 0
        if GetConsoleMode(input, &mode) {
            FileHandle.standardError.write(Data(prompt.utf8))
            SetConsoleMode(input, mode & ~DWORD(ENABLE_ECHO_INPUT))
            defer {
                SetConsoleMode(input, mode)
                FileHandle.standardError.write(Data("\n".utf8))
            }
            var buffer = [WCHAR](repeating: 0, count: 8192)
            var read: DWORD = 0
            guard ReadConsoleW(input, &buffer, DWORD(buffer.count), &read, nil), read > 0 else { return nil }
            return String(decoding: buffer.prefix(Int(read)), as: UTF16.self)
        }
    }
    #endif
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
}
