import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// A settings window's frames may be larger than a DLL's (§2.2): the user's English words, as many as are kept and each as
/// long as one may be, go with the list the window showed (§12.4).
extension WireSettingsTests {
    /// `EnglishWords.maxWords` words of `EnglishWords.maxLength` characters, each of its own letters.
    static var longestWords: [String] {
        (0..<EnglishWords.maxWords).map { i in
            let letters = String((0..<3).map { Character(Unicode.Scalar(UInt8(97 + (i / [1, 26, 676][$0]) % 26))) })
            let word = "Frob" + letters + " Toolkit Engine Platform Studio Pro"
            return String(word.prefix(EnglishWords.maxLength))
        }
    }

    @Test func aWindowSendsTheLongestListOfEnglishWords() throws {
        let words = Self.longestWords
        #expect(words.allSatisfy { EnglishWords.word($0) == $0 && $0.count == EnglishWords.maxLength })
        #expect(Set(words.map(EnglishWords.key)).count == words.count)
        let config = try json(["inputLanguages": ["zh", "en"], "englishWords": words, "addedEnglishWords": words])
        let (engine, id, welcome) = engine(config)
        #expect(welcome?.capabilities == [Hello.settings])
        // The window's edit of the line it showed (the newest first): the oldest word out, one in.
        let shown = words.reversed().joined(separator: ", ")
        let edited = (["Frobnicate"] + words.reversed().dropLast()).joined(separator: ", ")
        let frame = ClientFrame(id: 2, .settingsSet(field: "englishWords", value: .string(edited), shown: .string(shown)))
        let body = try WireJSON.encode(frame)
        #expect(body.count > WireFrame.clientLimit && body.count <= WireFrame.settingsClientLimit, "\(body.count) bytes")
        #expect(engine.server.clientLimit(on: id) == WireFrame.settingsClientLimit)
        let answer = engine.send(frame, on: id)
        guard case let .settings(re, settings)? = answer.first?.message else {
            Issue.record("not the settings: \(answer.map(\.message.type))")
            return
        }
        #expect(re == 2 && settings.problem == nil)
        guard case let .array(values)? = settings.document?.field("englishWords")?.value else {
            Issue.record("no englishWords")
            return
        }
        let saved = values.compactMap { if case let .string(word) = $0 { word } else { nil } }
        #expect(saved.count == EnglishWords.maxWords && saved.first == "Frobnicate" && !saved.contains(words[0]))
        // A DLL's frame is still 64 KiB at most: the same frame from a client without the settings closes it (§2.2).
        let (dll, dllID, _) = self.engine(config, capabilities: [])
        #expect(dll.server.clientLimit(on: dllID) == WireFrame.clientLimit)
        let refused = dll.send(body, on: dllID)
        #expect(refused.count == 1 && (try? WireJSON.decode(EngineFrame.self, from: refused[0]))?.message
                == .error(re: nil, code: .tooLarge, message: "frame of \(body.count) bytes is over the limit"))
        #expect(!dll.server.isOpen(dllID))
    }

    /// A client that asks for the settings and may not have them (low integrity, an AppContainer, one the transport said
    /// nothing about: §8) keeps a DLL's limit: the same frame closes its connection (§2.2).
    @Test func anUntrustedClientThatAsksForTheSettingsKeepsADLLsLimit() throws {
        let words = Self.longestWords
        let config = try json(["inputLanguages": ["zh", "en"], "englishWords": words, "addedEnglishWords": words])
        let line = words.reversed().joined(separator: ", ")
        let body = try WireJSON.encode(ClientFrame(id: 2, .settingsSet(field: "englishWords", value: .string(line), shown: .string(line))))
        #expect(body.count > WireFrame.clientLimit && body.count <= WireFrame.settingsClientLimit, "\(body.count) bytes")
        for peer in [WirePeer(integrity: .low), WirePeer(integrity: .medium, appContainer: true), WirePeer()] {
            let (engine, id, welcome) = self.engine(config, peer: peer)
            #expect(welcome?.capabilities == [], "\(peer)")
            #expect(engine.server.clientLimit(on: id) == WireFrame.clientLimit, "\(peer)")
            let refused = engine.send(body, on: id)
            #expect(refused.count == 1 && (try? WireJSON.decode(EngineFrame.self, from: refused[0]))?.message
                    == .error(re: nil, code: .tooLarge, message: "frame of \(body.count) bytes is over the limit"), "\(peer)")
            #expect(!engine.server.isOpen(id), "\(peer)")
        }
    }
}
