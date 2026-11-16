import Foundation
import Testing
@testable import AllInOneIMECore

/// Reproduction (AGENTS.md rule 20) of a suspicion from a code read: the default Bedrock model is a US cross-region
/// inference profile ("us.anthropic.claude-haiku-4-5-…"), and with no region set the request goes to the AWS profile's
/// region; with a profile outside the US every request then fails, with an error that doesn't say why.
///
/// Bedrock is stubbed (rule 12) by `GeographyBedrock`, which answers as Bedrock does: an inference profile only in a
/// region of its geography ("us." in us-*, "eu." in eu-*, …, "global." anywhere), else HTTP 400 ValidationException
/// "The provided model identifier is invalid."; Claude Haiku 4.5 without a profile isn't served on demand.
@Suite(.serialized)
struct BedrockProfileRegionTests {
    func collect(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> [ConversionUpdate] {
        var updates: [ConversionUpdate] = []
        for try await update in stream { updates.append(update) }
        return updates
    }

    /// The defaults (no region of their own) with `config` changed, credentials from a profile whose region is
    /// `profileRegion`.
    func converter(profileRegion: String, _ change: (inout Config) -> Void = { _ in }) -> Converter {
        var config = Config.default
        config.awsProfile = "test"
        change(&config)
        let fixed = config
        return Converter(
            client: BedrockClient(session: GeographyBedrock.session()),
            loadConfig: { fixed },
            loadCredentials: { _ in
                AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "secret"),
                                         region: profileRegion)
            },
            hasAWSProfile: { _ in true })
    }

    /// A user whose AWS profile is in Europe (or Tokyo) sets up nothing but the profile: `@improve` answers.
    @Test(arguments: ["eu-west-1", "ap-northeast-1"])
    func theDefaultModelAnswersWithAProfileOutsideTheUS(region: String) async throws {
        #expect(Config.default.region == nil)
        GeographyBedrock.reset(region)
        do {
            let updates = try await collect(converter(profileRegion: region).convert("我今天有点不舒服"))
            #expect(updates.last?.isFinal == true && updates.last?.result.versions.isEmpty == false)
        } catch {
            let sent = GeographyBedrock.models(region)
            Issue.record("a profile in \(region): \(UIText.$scopedLanguage.withValue("en") { UIText.describe(error) }) (asked \(region) for \(sent))")
        }
    }

    /// Region and model set by hand to a pair Bedrock refuses (eu-central-1 with a "us." profile): whatever the app does
    /// about it, the error it shows says the region is the cause, not only "The provided model identifier is invalid."
    @Test func aModelOfAnotherGeographySaysTheRegionIsWhy() async throws {
        let region = "eu-central-1"
        GeographyBedrock.reset(region)
        let converter = converter(profileRegion: "us-east-1") {
            $0.region = region
            $0.modelId = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
        }
        do {
            _ = try await collect(converter.convert("我今天有点不舒服"))
        } catch {
            let shown = UIText.$scopedLanguage.withValue("en") { UIText.describe(error) }
            #expect(shown.contains(region), "what the panel shows: \"\(shown)\"")
        }
    }
}

/// bedrock-runtime as it answers a model ID in a region (see `BedrockProfileRegionTests`); the stream it answers with is
/// the captured one the other Bedrock tests use. Each test resets the region it asks, and runs alone (`.serialized`).
final class GeographyBedrock: URLProtocol, @unchecked Sendable {
    private static let asked = Locked<[String: [String]]>(initialState: [:])

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeographyBedrock.self]
        return URLSession(configuration: configuration)
    }

    static func reset(_ region: String) { asked.withLock { $0[region] = [] } }

    /// The model IDs asked for in `region`, in order.
    static func models(_ region: String) -> [String] { asked.withLock { $0[region] ?? [] } }

    /// Whether Bedrock serves `model` in `region`: a cross-region profile in its own geography's regions, a global one
    /// anywhere, Claude Haiku 4.5 only through a profile.
    static func serves(_ model: String, in region: String) -> Bool {
        let geographies: [(prefix: String, regions: (String) -> Bool)] = [
            ("us.", { $0.hasPrefix("us-") && !$0.hasPrefix("us-gov-") }), ("us-gov.", { $0.hasPrefix("us-gov-") }),
            ("eu.", { $0.hasPrefix("eu-") }), ("apac.", { $0.hasPrefix("ap-") }),
            ("jp.", { ["ap-northeast-1", "ap-northeast-3"].contains($0) }), ("au.", { ["ap-southeast-2", "ap-southeast-4"].contains($0) }),
            ("ca.", { $0.hasPrefix("ca-") }), ("global.", { _ in true }),
        ]
        if let geography = geographies.first(where: { model.hasPrefix($0.prefix) }) { return geography.regions(region) }
        return !model.hasPrefix("anthropic.claude-haiku-4-5")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, host.hasPrefix("bedrock-runtime."), host.hasSuffix(".amazonaws.com"),
              request.httpMethod == "POST"
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let region = String(host.dropFirst("bedrock-runtime.".count).dropLast(".amazonaws.com".count))
        // /model/<id>/converse-stream, the ID percent-encoded.
        let parts = url.path.split(separator: "/")
        let model = parts.count >= 2 ? String(parts[1]).removingPercentEncoding ?? String(parts[1]) : ""
        Self.asked.withLock { $0[region, default: []].append(model) }
        let status: Int, headers: [String: String], body: Data
        if Self.serves(model, in: region), let stream = try? fixture("bedrock-converse-stream") {
            (status, headers, body) = (200, ["Content-Type": "application/vnd.amazon.eventstream"], Data(stream))
        } else {
            let message = model.hasPrefix("anthropic.")
                ? "Invocation of model ID \(model) with on-demand throughput isn’t supported. Retry your request with the ID or ARN of an inference profile that contains this model."
                : "The provided model identifier is invalid."
            (status, headers, body) = (400, ["x-amzn-ErrorType": "ValidationException:http://internal.amazon.com/coral/com.amazon.bedrock/",
                                             "Content-Type": "application/json"],
                                       Data(#"{"message":"\#(message)"}"#.utf8))
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
