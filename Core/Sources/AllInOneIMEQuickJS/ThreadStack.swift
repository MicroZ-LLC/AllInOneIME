#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import WinSDK
#endif
#if !canImport(Darwin) && !os(Windows)
internal import CQuickJS  // QJS_ThreadStack
#endif

/// The stack of the thread a script runs on, from where the caller is. QuickJS checks how deep a script goes against a
/// size it is told, and throws ("RangeError: Maximum call stack size exceeded") when it gets there: that size has to fit
/// in what the thread has left, which differs (1 MB on Windows by default, 512 KB for a secondary thread on Apple
/// platforms, 8 MB for a main thread elsewhere). Swift's own conversions of nested values check it too (`floor`).
struct ThreadStack {
    /// The bytes below the caller's frame; nil where the stack can't be read.
    let left: Int?
    /// The lowest place Swift's own conversions go (`QuickJSRuntime.object(of:)`, `makeValue`): `margin` above the end of
    /// the stack; 0 where the stack can't be read (they stop at `QuickJSRuntime.maxDepth` alone).
    let floor: UInt

    /// What Swift's conversions leave of the stack: room for the frames below their last check, and the system's guard
    /// pages.
    static let margin = 64 << 10

    /// This thread's, from the caller.
    static func current() -> ThreadStack {
        let here = here()
        guard let bottom = bottom(), here > bottom else { return ThreadStack(left: nil, floor: 0) }
        return ThreadStack(left: Int(here - bottom), floor: bottom + UInt(margin))
    }

    /// How deep scripts may go from here: half of what is left (the other half for the frames QuickJS and native functions
    /// make between its checks, and Swift's conversions), at most QuickJS's default, 1 MB; 256 KB where the stack can't
    /// be read.
    var scriptLimit: Int {
        guard let left else { return 256 << 10 }
        return max(16 << 10, min(1 << 20, left / 2))
    }

    /// Where the caller is on its stack, which grows down: the address of a local, just below the caller's frame.
    @inline(never)
    static func here() -> UInt {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
    }

    /// The lowest address of this thread's stack.
    private static func bottom() -> UInt? {
        #if canImport(Darwin)
        let thread = pthread_self()
        return UInt(bitPattern: pthread_get_stackaddr_np(thread)) - UInt(pthread_get_stacksize_np(thread))
        #elseif os(Windows)
        var low: ULONG_PTR = 0, high: ULONG_PTR = 0
        GetCurrentThreadStackLimits(&low, &high)
        return UInt(low)
        #elseif canImport(Glibc) || canImport(Musl) || canImport(Android)
        // pthread_getattr_np, through CQuickJS: Swift's Glibc doesn't declare it (quickjs-swift.h).
        var address: UnsafeMutableRawPointer?
        var size = 0
        guard QJS_ThreadStack(&address, &size) == 0, let address else { return nil }
        return UInt(bitPattern: address)
        #else
        return nil
        #endif
    }
}
