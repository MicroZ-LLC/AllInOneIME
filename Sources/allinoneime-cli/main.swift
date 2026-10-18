import AllInOneIMECLI
import AllInOneIMECore
import AllInOneIMEMac

// The core's command line (AllInOneIMECLI) with the Mac's platform: programs with the login shell's environment.
// Settings from the AIPinyin days move to ~/.config/allinoneime first, once the options are read.
Platform.current = .mac
await CLI.run(prepare: { LegacyData.migrate() })
