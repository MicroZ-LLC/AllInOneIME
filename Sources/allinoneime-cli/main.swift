import AllInOneIMECLI
import AllInOneIMECore
import AllInOneIMEMac

// The core's command line (AllInOneIMECLI) with the Mac's platform: programs with the login shell's environment.
Platform.current = .mac
await CLI.run()
