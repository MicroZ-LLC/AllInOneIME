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

    /// A row's image is read off the window's thread: one that doesn't come (a share that doesn't answer; here a pipe
    /// that never writes) holds nothing up, the panel drawn at once with the fallback.
    @Test(.timeLimit(.minutes(1))) func anImageThatDoesntComeHoldsNothingUp() throws {
        let window = try window()
        let owner = PanelOwner(pid: nil, choose: { _ in })
        let name = #"\\.\pipe\aio-slow-image-"# + "\(GetCurrentProcessId())-\(UInt32.random(in: 0...UInt32.max))"
        var servers: [HANDLE] = []
        defer { for server in servers { CloseHandle(server) } }
        for _ in 0..<4 {
            let server = name.withCString(encodedAs: UTF16.self) {
                CreateNamedPipeW($0, DWORD(PIPE_ACCESS_DUPLEX), DWORD(PIPE_TYPE_BYTE), 4, 4096, 4096, 0, nil)
            }
            if let server, server != INVALID_HANDLE_VALUE { servers.append(server) }
        }
        try #require(!servers.isEmpty)
        var model = Self.model
        model.rows[0].icon = IconToken(.image(path: name, fallback: .scriptList), color: .teal)
        let started = Date()
        window.show(model, owner: owner, caret: Self.caret)
        let state = window.state  // once the window's thread has done what was posted (it waits 5 s at most)
        #expect(Date().timeIntervalSince(started) < 2, "the window's thread waited for the image")
        #expect(state.visible == 1)
        window.hide(owner: owner)
        #expect(window.state.visible == 0)
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
