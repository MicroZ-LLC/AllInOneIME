import AllInOneIMECLI
import Foundation

// The core's command line on the core's own platform (`Platform()`: on Windows its Platform/Windows/ implementations,
// the Credential Manager for API keys, programs in job objects, the Recycle Bin). What else the shell brings (its
// environment) comes with the input method.
// `wire-replay` is the Windows shell's own: the wire protocol's goldens over the engine's pipe.
if CommandLine.arguments.dropFirst().first == "wire-replay" {
    exit(WireReplay.main(Array(CommandLine.arguments.dropFirst(2))))
}
await CLI.run()
