import Foundation
import Testing

/// The English words the input method learns are written into the config file off the main thread
/// (`EnglishWords.Writer`, whose keeping and draining the core's tests show): what it couldn't write yet is tried again
/// once the file reads anew and parses, and drained before the input method ends, on SIGTERM (an update, `make install`,
/// logging out) and when it terminates (the updater's quit). Read from the sources, as the input method can't be run here.
struct EnglishWordsWriterTests {
    @Test func whatWasLearnedIsDrainedBeforeTheInputMethodEnds() throws {
        let main = try InputMenuWritesTests.source("main.swift")
        let terminate = try #require(InputMenuWritesTests.body(of: "applicationWillTerminate", in: main))
        #expect(terminate.contains("SessionServices.englishWordsWriter.drain(within:"))
        let signal = try #require(main.range(of: "source.setEventHandler {").map { main[$0.upperBound...] })
        let handler = try #require(signal.range(of: "_exit(0)\n").map { signal[..<$0.lowerBound] })
        #expect(handler.contains("SessionServices.englishWordsWriter.drain(within:"), "\(handler)")
    }

    @Test func whatCouldntBeWrittenIsTriedAgainOnceTheFileParses() throws {
        let live = try InputMenuWritesTests.source("LiveSettings.swift")
        let read = try #require(live.range(of: "static var currentIfValid: Config? {").map { live[$0.upperBound...] })
        let body = try #require(read.range(of: "\n    }\n").map { read[..<$0.lowerBound] })
        #expect(body.contains("if config != nil { parsedAnew() }"), "\(body)")
        let server = try #require(InputMenuWritesTests.body(of: "runServer", in: try InputMenuWritesTests.source("main.swift")))
        #expect(server.contains("LiveConfig.parsedAnew = { SessionServices.englishWordsWriter.retry() }"))
    }
}
