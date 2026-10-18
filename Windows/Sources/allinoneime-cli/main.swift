import AllInOneIMECLI
import Foundation

// The core's command line on the core's own platform (`Platform()`: what Foundation has on Windows). A Windows
// platform of its own (the credential store for API keys, the shell's environment) comes with the input method.
// `wire-replay` is the Windows shell's own: the wire protocol's goldens over the engine's pipe.
if CommandLine.arguments.dropFirst().first == "wire-replay" {
    exit(WireReplay.main(Array(CommandLine.arguments.dropFirst(2))))
}
await CLI.run()
