// On the Mac, the core's tests that predate the macOS shell's library (AllInOneIMEMac) still find what moved there: the
// real git (`ProcessGitRunner`) and the login shell (`ShellEnvironment`). Elsewhere those tests are left out (Package.swift).
#if canImport(AllInOneIMEMac)
@_exported import AllInOneIMEMac
#endif
