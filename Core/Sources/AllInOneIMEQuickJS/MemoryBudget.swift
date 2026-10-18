import Foundation
internal import CQuickJS

/// What a runtime may allocate (`QuickJSEngine.memoryLimit`), held by the allocator QuickJS is given (`newRuntime`)
/// rather than by QuickJS's own limit (`JS_SetMemoryLimit`), which leaves no room for the error that says it was
/// reached (QuickJS throws null instead). Past this one a reserve opens, for that error, its message and its stack (and
/// whatever runs before the next call into QuickJS, `reset`). Used from the runtime's thread.
final class MemoryBudget {
    let limit: Int
    /// The bytes allocated.
    private(set) var used = 0
    /// Whether an allocation was refused since the reserve last closed: it is open.
    private var exceeded = false

    /// What the error takes, and more.
    static let reserve = 256 << 10
    /// Each block's size, in front of it: 16 bytes, which keeps malloc's alignment.
    static let header = 16

    init(limit: Int) {
        self.limit = limit
    }

    /// A new runtime whose memory this is (nil when there is none for it). This must outlive it.
    func newRuntime() -> OpaquePointer? {
        var functions = JSMallocFunctions(
            js_calloc: { opaque, count, size in
                let (total, overflow) = count.multipliedReportingOverflow(by: size)
                return overflow ? nil : MemoryBudget.of(opaque).allocate(total, zeroed: true)
            },
            js_malloc: { opaque, size in MemoryBudget.of(opaque).allocate(size, zeroed: false) },
            js_free: { opaque, block in
                if let block { MemoryBudget.of(opaque).release(block) }
            },
            js_realloc: { opaque, block, size in
                guard let block else { return MemoryBudget.of(opaque).allocate(size, zeroed: false) }
                return MemoryBudget.of(opaque).reallocate(block, to: size)
            },
            js_malloc_usable_size: { block in block.map(MemoryBudget.size(of:)) ?? 0 }
        )
        return JS_NewRuntime2(&functions, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Closes the reserve, once what was allocated past the limit is freed: before each outermost call into QuickJS.
    func reset() {
        if used <= limit { exceeded = false }
    }

    // MARK: - The allocator

    private static func of(_ opaque: UnsafeMutableRawPointer?) -> MemoryBudget {
        Unmanaged<MemoryBudget>.fromOpaque(opaque!).takeUnretainedValue()
    }

    /// Whether `more` bytes may be allocated: within the limit, or within the reserve once an allocation was refused.
    private func allows(_ more: Int) -> Bool {
        if more <= 0 || used + more <= limit { return true }
        if exceeded { return used + more <= limit + Self.reserve }
        exceeded = true
        return false
    }

    private func allocate(_ size: Int, zeroed: Bool) -> UnsafeMutableRawPointer? {
        guard size <= Int.max - Self.header, allows(size),
              let block = zeroed ? calloc(1, size + Self.header) : malloc(size + Self.header) else { return nil }
        block.storeBytes(of: size, as: Int.self)
        used += size
        return block + Self.header
    }

    private func reallocate(_ block: UnsafeMutableRawPointer, to size: Int) -> UnsafeMutableRawPointer? {
        let old = Self.size(of: block)
        guard size <= Int.max - Self.header, allows(size - old),
              let moved = realloc(block - Self.header, size + Self.header) else { return nil }
        moved.storeBytes(of: size, as: Int.self)
        used += size - old
        return moved + Self.header
    }

    private func release(_ block: UnsafeMutableRawPointer) {
        used -= Self.size(of: block)
        free(block - Self.header)
    }

    private static func size(of block: UnsafeRawPointer) -> Int {
        (block - header).load(as: Int.self)
    }
}
