#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import CAllInOneIMEPanel
import Foundation
import Testing
import WinSDK

extension OnTheDesktop.CandidateWindowTests {
    /// A 16 × 16 BMP of one color.
    static func bmp(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        let side = 16, row = side * 3
        var data = Data()
        func u16(_ value: Int) { data += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func u32(_ value: Int) { u16(value & 0xFFFF); u16(value >> 16 & 0xFFFF) }
        data += [0x42, 0x4D]
        u32(54 + row * side); u32(0); u32(54)
        u32(40); u32(side); u32(side); u16(1); u16(24); u32(0); u32(row * side); u32(2835); u32(2835); u32(0); u32(0)
        for _ in 0..<(side * side) { data += [blue, green, red] }
        return data
    }

    /// `window` drawn again after `draws` draws (an image read since), within `seconds`.
    func drawnAgain(_ window: CandidateWindow, after draws: Int32, within seconds: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while window.state.draws <= draws, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        return window.state.draws > draws
    }

    /// A row's image is read off the window's thread: one that doesn't come (a share that doesn't answer: `StuckFiles`)
    /// holds nothing up, the panel drawn at once with the fallback. (A named pipe that never writes, as this had it, is
    /// no such file: the read fails at once.)
    @Test(.timeLimit(.minutes(1))) func anImageThatDoesntComeHoldsNothingUp() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        let stuck = try StuckFiles(1)
        defer { withExtendedLifetime(stuck) {} }
        var model = Self.model
        model.rows[0].icon = IconToken(.image(path: stuck.paths[0], fallback: .scriptList), color: .teal)
        let started = Date()
        window.show(model, owner: owner, caret: Self.caret)
        let state = window.state  // once the window's thread has done what was posted (it waits 5 s at most)
        #expect(Date().timeIntervalSince(started) < 2, "the window's thread waited for the image")
        #expect(state.visible == 1)
        window.hide(owner: owner)
        #expect(window.state.visible == 0)
    }

    /// Files whose read doesn't end while this holds them (a share that doesn't answer): each with a batch oplock of this
    /// process's, which another open breaks and waits for until the oplock goes with this (an open for the attributes
    /// alone, as the loader's look at the file's time and size, doesn't).
    final class StuckFiles {
        let folder: URL
        let paths: [String]
        private var held: [(handle: HANDLE, overlapped: UnsafeMutablePointer<OVERLAPPED>)] = []

        init(_ count: Int) throws {
            let folder = try temporaryFolder("panel-stuck-images")
            self.folder = folder
            paths = (0..<count).map { index in
                folder.appendingPathComponent("\(index).bmp").withUnsafeFileSystemRepresentation { String(cString: $0!) }
            }
            for path in paths {
                _ = FileManager.default.createFile(atPath: path, contents: OnTheDesktop.CandidateWindowTests.bmp(red: 0, green: 128, blue: 0))
                let handle = path.withCString(encodedAs: UTF16.self) {
                    CreateFileW($0, GENERIC_READ, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                                DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_OVERLAPPED), nil)
                }
                guard let handle, handle != INVALID_HANDLE_VALUE else { throw Self.failed("CreateFileW") }
                let overlapped = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
                overlapped.initialize(to: OVERLAPPED())
                overlapped.pointee.hEvent = CreateEventW(nil, true, false, nil)
                held.append((handle, overlapped))
                // FSCTL_REQUEST_BATCH_OPLOCK: granted while it is pending.
                guard !DeviceIoControl(handle, 0x0009_0008, nil, 0, nil, 0, nil, overlapped), GetLastError() == DWORD(ERROR_IO_PENDING)
                else { throw Self.failed("FSCTL_REQUEST_BATCH_OPLOCK") }
            }
        }

        static func failed(_ call: String) -> Error {
            CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "\(call): \(GetLastError())"])
        }

        deinit {
            for (handle, overlapped) in held {
                CancelIoEx(handle, overlapped)
                CloseHandle(handle)
                CloseHandle(overlapped.pointee.hEvent)
            }
            // The loader's reads end once the oplocks are gone; their memory is left (a test's).
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Images whose reads don't end hold up no other: the one after two of them is read and drawn (another reader once
    /// theirs have run a second).
    @Test(.timeLimit(.minutes(1))) func stuckImagesHoldUpNoOther() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        let stuck = try StuckFiles(2)
        defer { withExtendedLifetime(stuck) {} }  // the pipes stay till the end
        let folder = try temporaryFolder("panel-stuck-image")
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("icon.bmp")
        try Self.bmp(red: 255, green: 0, blue: 0).write(to: image)
        var model = Self.model
        model.rows[0].icon = IconToken(.image(path: stuck.paths[0], fallback: .scriptList), color: .teal)
        model.rows[1].icon = IconToken(.image(path: stuck.paths[1], fallback: .scriptList), color: .teal)
        model.rows[2].icon = IconToken(.image(path: image.withUnsafeFileSystemRepresentation { String(cString: $0!) },
                                              fallback: .scriptList), color: .teal)
        window.show(model, owner: owner, caret: Self.caret)
        let draws = window.state.draws
        #expect(draws >= 1)
        #expect(drawnAgain(window, after: draws), "the image after the stuck ones never came")
        window.hide(owner: owner)
    }

    /// The images being read count against the 64 kept: with more whose reads don't end, no more are kept (their
    /// fallback drawn), however many rows ask.
    @Test(.timeLimit(.minutes(1))) func imagesBeingReadCountAgainstTheLimit() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        let stuck = try StuckFiles(72)
        defer { withExtendedLifetime(stuck) {} }
        var model = Self.model
        for start in stride(from: 0, to: stuck.paths.count, by: model.rows.count) {
            for row in model.rows.indices {
                model.rows[row].icon = IconToken(.image(path: stuck.paths[start + row], fallback: .scriptList), color: .teal)
            }
            window.show(model, owner: owner, caret: Self.caret)
            #expect(window.state.images <= 64)
        }
        #expect(window.state.images == 64)
        #expect(window.state.visible == 1)
        window.hide(owner: owner)
    }

    /// An image that couldn't be read is drawn once it can be, and one that changed is read again: looked at again in
    /// the background as the panel is drawn, every 2 s at most.
    @Test(.timeLimit(.minutes(1))) func anImageIsReadAgainOnceItChanged() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        let folder = try temporaryFolder("panel-image")
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("icon.bmp")
        try Data("not an image".utf8).write(to: image)
        var model = Self.model
        let path = image.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        model.rows[0].icon = IconToken(.image(path: path, fallback: .scriptList), color: .teal)
        func png(_ name: String) throws -> Data {
            let file = folder.appendingPathComponent(name)
            #expect(window.savePNG(to: file))
            return try Data(contentsOf: file)
        }
        window.show(model, owner: owner, caret: Self.caret)
        #expect(window.state.visible == 1)
        Thread.sleep(forTimeInterval: 0.5)  // tried, and not readable: the fallback stays
        let unreadable = try png("unreadable.png")
        // Readable now: drawn at the first draw 2 s or more after it was looked at.
        try Self.bmp(red: 255, green: 0, blue: 0).write(to: image)
        Thread.sleep(forTimeInterval: 2.2)
        var draws = window.state.draws
        window.show(model, owner: owner, caret: Self.caret)
        #expect(drawnAgain(window, after: draws + 1))
        let red = try png("red.png")
        #expect(red != unreadable)
        // Changed: read again.
        try Self.bmp(red: 0, green: 0, blue: 255).write(to: image)
        Thread.sleep(forTimeInterval: 2.2)
        draws = window.state.draws
        window.show(model, owner: owner, caret: Self.caret)
        #expect(drawnAgain(window, after: draws + 1))
        let blue = try png("blue.png")
        #expect(blue != red && blue != unreadable)
        window.hide(owner: owner)
    }
}
#endif
