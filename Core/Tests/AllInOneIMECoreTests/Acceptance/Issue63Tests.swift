import Foundation
import Testing
@testable import AllInOneIMECore

/// #63: a Settings → Assistant request too long for Apple Intelligence on this Mac goes to the user's own provider
/// instead. With Amazon Bedrock chosen and no usable AWS profile on this Mac (the provider synced from another Mac, say),
/// the page says "Amazon Bedrock couldn't answer instead: AWS profile 'default' not found", where every other provider
/// that isn't set up gets "isn't set up: try a shorter request, or set up X in Settings → AI". Expected: the same
/// "isn't set up" line for Bedrock with no such profile, or a profile with no credentials in it; an SSO sign-in that
/// is missing or expired still says what Bedrock's credentials said ("run aws sso login …"). Through
/// `AIConfigService.ask` as the page sends it, with the on-device model always too long and the profile's credentials
/// loaded as the live resolver fails (`AWSCredentialError`); the line as the page shows it (`UIText.describe`).
struct Issue63Tests {
    /// Stands in for Apple Intelligence on this Mac: available, and every request too long for its context, fitted or not.
    final class AlwaysTooLongModel: AppleGuidedBackend, @unchecked Sendable {
        let availability: AppleModelAvailability = .available
        let contextSize = 4096
        let supportedLanguages: Set<String> = ["en", "zh"]

        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish(throwing: AppleModelError.contextExceeded) }
        }

        func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
            throw AppleModelError.contextExceeded
        }
    }

    /// Bedrock chosen, its profile "default"; its credentials fail with `credentialError`, as the resolver's do.
    static func service(failingWith credentialError: AWSCredentialError) -> AIConfigService {
        AIConfigService(client: ChatClient(apple: AlwaysTooLongModel()), loadCredentials: { _ in throw credentialError },
                        loadKey: { _, _ in nil })
    }

    static func context() -> AIConfigPrompt.Context {
        var config = Config.default
        config.provider = .bedrock
        config.awsProfile = "default"
        return AIConfigPrompt.Context(config: config, offeredProviders: [.bedrock, .anthropic, .gemini, .openai, .apple])
    }

    /// What the request threw, as `TooLong`.
    static func tooLong(failingWith credentialError: AWSCredentialError) async throws -> AIConfigService.TooLong {
        do {
            _ = try await service(failingWith: credentialError).ask("candidates in a column", context: context())
        } catch let error as AIConfigService.TooLong {
            return error
        }
        Issue.record("the request didn't fail as too long")
        throw CancellationError()
    }

    /// The line Settings → Assistant shows for `error`, in `language`.
    static func line(_ error: any Error, language: String) -> String {
        UIText.$scopedLanguage.withValue(language) { UIText.describe(error) }
    }

    /// How the credentials of a Bedrock that isn't set up fail.
    enum NotSetUp: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// No such profile on this Mac.
        case profileNotFound
        /// The profile is there with nothing that gives credentials (only a region, say).
        case noCredentials
        var testDescription: String { rawValue }

        var error: AWSCredentialError {
            switch self {
            case .profileNotFound: return .profileNotFound("default")
            case .noCredentials: return .noCredentials(profile: "default")
            }
        }
    }

    /// The issue's case: Bedrock isn't set up on this Mac. The page says to set it up, as for any other provider; not
    /// that Bedrock couldn't answer.
    @Test(arguments: NotSetUp.allCases)
    func bedrockWithoutAProfileIsNotSetUp(_ notSetUp: NotSetUp) async throws {
        let error = try await Self.tooLong(failingWith: notSetUp.error)
        #expect(error.provider == .bedrock)
        #expect(error.providerError as? AWSCredentialError == notSetUp.error)
        #expect(error.providerNotSetUp, "Bedrock with \(notSetUp.error) counted as having failed, not as not set up")
        #expect(Self.line(error, language: "en")
            == "Too long for Apple Intelligence on this Mac, and Amazon Bedrock isn't set up: try a shorter request, or set up Amazon Bedrock in Settings → AI")
        #expect(Self.line(error, language: "zh-Hans")
            == "这句话对本机的 Apple Intelligence 来说太长了，Amazon Bedrock 也还没设置好：请说得短一些，或者在设置 → AI 里设置好 Amazon Bedrock")
    }

    /// The issue's own check, without a request.
    @Test func theIssuesCase() {
        #expect(AIConfigService.TooLong(provider: .bedrock, providerError: AWSCredentialError.profileNotFound("default")).providerNotSetUp)
        #expect(AIConfigService.TooLong(provider: .bedrock, providerError: AWSCredentialError.noCredentials(profile: "default")).providerNotSetUp)
    }

    /// An SSO sign-in missing or expired is left as it is: the page still says what to run.
    @Test(arguments: [AWSCredentialError.ssoNotSignedIn(profile: "default"), .ssoExpired(profile: "default")])
    func anSSOSignInStillSaysWhatToRun(_ credentialError: AWSCredentialError) async throws {
        let error = try await Self.tooLong(failingWith: credentialError)
        #expect(error.provider == .bedrock && !error.providerNotSetUp)
        let line = Self.line(error, language: "en")
        #expect(line.hasPrefix("Too long for Apple Intelligence on this Mac, and Amazon Bedrock couldn't answer instead: "))
        #expect(line.contains("aws sso login --profile default"), "\(line)")
    }
}
