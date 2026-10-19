import Foundation

extension NSNumber {
    /// Whether this is `true` or `false` as JSONSerialization and PropertyListSerialization read them, not the
    /// numbers 1 and 0: Foundation's two boolean instances (CFBoolean on Apple platforms), which `NSNumber(value:)`
    /// gives back for a Bool. Comparing those works everywhere; `CFGetTypeID` and `kCFBooleanTrue` are Apple's.
    var isBoolean: Bool {
        self === NSNumber(value: true) || self === NSNumber(value: false)
    }
}
