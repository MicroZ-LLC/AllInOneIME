import Foundation
import Testing
@testable import AllInOneIMECore

/// A test of the Mac's own text (its key symbols, "this Mac", Terminal, `.app` bundles: `PlatformTerms.mac`), whatever
/// the system the tests run on: `Platform.current.terms` is the Mac's while it runs (through `Platform.override`), as
/// the Mac's shell has it. On Windows the core's defaults are Windows' terms, which a test pins with `terms: .windows`.
struct MacTerms: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> MacTerms? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        var platform = Platform.current
        platform.terms = .mac
        try await Platform.$override.withValue(platform) { try await function() }
    }
}
