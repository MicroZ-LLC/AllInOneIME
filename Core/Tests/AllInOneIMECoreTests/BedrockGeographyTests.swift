import Foundation
import os
import Testing
@testable import AllInOneIMECore

/// Bedrock's model ID sent with the inference profile of the region's own geography (`BedrockGeography`), and the
/// error that names the model and the region when Bedrock still refuses it. Bedrock is stubbed (`GeographyRecorder`).
@Suite(.serialized)
struct BedrockGeographyTests {
    static let haiku = "anthropic.claude-haiku-4-5-20251001-v1:0"

    @Test(arguments: [
        // A "us." profile outside the US: the region's geography's, as the models' cards list them.
        ("us." + haiku, "eu-west-1", "eu." + haiku), ("us." + haiku, "eu-central-2", "eu." + haiku),
        ("us." + haiku, "ap-northeast-1", "jp." + haiku), ("us." + haiku, "ap-northeast-3", "jp." + haiku),
        ("us." + haiku, "ap-southeast-2", "au." + haiku), ("us." + haiku, "ap-southeast-6", "au." + haiku),
        ("us." + haiku, "ap-south-1", "in." + haiku),
        ("us." + haiku, "ap-northeast-2", "apac." + haiku),  // Seoul: only the older models' APAC profiles
        // Each way: another geography's into the US's, Europe's.
        ("eu.anthropic.claude-sonnet-4-6", "us-east-1", "us.anthropic.claude-sonnet-4-6"),
        ("jp.amazon.nova-2-lite-v1:0", "eu-central-1", "eu.amazon.nova-2-lite-v1:0"),
        ("apac.amazon.nova-lite-v1:0", "us-west-2", "us.amazon.nova-lite-v1:0"),
        // A profile the region can call: as it is.
        ("us." + haiku, "us-west-2", "us." + haiku), ("us." + haiku, "us-east-1", "us." + haiku),
        ("us." + haiku, "ca-central-1", "us." + haiku), ("us." + haiku, "us-gov-west-1", "us." + haiku),
        ("eu." + haiku, "eu-west-2", "eu." + haiku), ("jp." + haiku, "ap-northeast-1", "jp." + haiku),
        ("apac.anthropic.claude-sonnet-4-20250514-v1:0", "ap-northeast-1", "apac.anthropic.claude-sonnet-4-20250514-v1:0"),
        ("apac.amazon.nova-lite-v1:0", "ap-southeast-2", "apac.amazon.nova-lite-v1:0"),
        // A region of no geography: as it is (never "global.").
        ("us." + haiku, "sa-east-1", "us." + haiku), ("us." + haiku, "me-central-1", "us." + haiku),
        // Not a geography's profile: as it is.
        ("global." + haiku, "eu-west-1", "global." + haiku),
        ("anthropic.claude-sonnet-4-6", "eu-west-1", "anthropic.claude-sonnet-4-6"),
        ("amazon.nova-2-lite-v1:0", "ap-northeast-1", "amazon.nova-2-lite-v1:0"),
        ("ca.anthropic.claude-sonnet-4-6", "eu-west-1", "ca.anthropic.claude-sonnet-4-6"),
        ("arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/abc", "eu-west-1",
         "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/abc"),
        ("", "eu-west-1", ""),
    ] as [(String, String, String)])
    func modelIdForTheRegion(id: String, region: String, sent: String) {
        #expect(BedrockGeography.modelId(id, in: region) == sent)
    }

    /// Every region of a geography gets a profile of a geography that lists it, whatever profile it was given.
    @Test func everyListedRegionGetsAProfileItCanCall() {
        for region in BedrockGeography.geographies.flatMap(\.regions) {
            for given in BedrockGeography.geographies.map(\.prefix) {
                let sent = BedrockGeography.modelId(given + "." + Self.haiku, in: region)
                let prefix = String(sent.prefix { $0 != "." })
                #expect(BedrockGeography.geographies.contains { $0.prefix == prefix && $0.regions.contains(region) },
                        "\(given). in \(region): \(sent)")
            }
        }
    }

    /// The suggested models (the default among them) have a European and a Japanese profile, under the same name.
    @Test func theSuggestedModelsInEuropeAndJapan() {
        #expect(SuggestedModel.all.contains { $0.id == Config.default.modelId })
        for model in SuggestedModel.all {
            #expect(model.id.hasPrefix("us."))
            #expect(BedrockGeography.modelId(model.id, in: "eu-west-3") == "eu." + model.id.dropFirst(3))
            #expect(BedrockGeography.modelId(model.id, in: "ap-northeast-1") == "jp." + model.id.dropFirst(3))
        }
    }

    @Test func theRegionIsTheConfigsElseTheProfiles() {
        var config = Config.default
        #expect(config.bedrockRegion(profileRegion: "eu-west-1") == "eu-west-1")
        #expect(config.bedrockRegion(profileRegion: nil) == "us-east-1")
        config.region = "ap-southeast-2"
        #expect(config.bedrockRegion(profileRegion: "eu-west-1") == "ap-southeast-2")
        #expect(config.bedrockModelId(in: config.bedrockRegion(profileRegion: nil)) == "au." + Self.haiku)
    }

    @Test(arguments: [
        (BedrockError.http(status: 400, type: "ValidationException", message: "The provided model identifier is invalid."), true),
        (.http(status: 400, type: "ValidationException",
               message: "Invocation of model ID anthropic.claude-haiku-4-5 with on-demand throughput isn’t supported."), false),
        (.http(status: 400, type: "ValidationException", message: "temperature: range: 0..1"), false),
        (.http(status: 403, type: "AccessDeniedException", message: "You don't have access to the model with the specified model ID."), false),
        (.stream(type: "ValidationException", message: "The provided model identifier is invalid."), false),
        (.modelNotInRegion(model: "us.x", region: "eu-west-1"), false),
    ] as [(BedrockError, Bool)])
    func whichErrorsMeanAnInvalidModel(error: BedrockError, invalid: Bool) {
        #expect(error.isInvalidModel == invalid)
        #expect(!BedrockError.modelNotInRegion(model: "us.x", region: "eu-west-1").isExpiredCredentials)
    }

    /// Settings → AI's line under the model: only where the ID sent isn't the one set, with both it and the region.
    @Test func settingsSayWhichIdIsSent() {
        var config = Config.default
        UIText.$scopedLanguage.withValue("en") {
            #expect(UIText.bedrockModelSent(config, profileRegion: "us-west-2") == nil)
            #expect(UIText.bedrockModelSent(config, profileRegion: nil) == nil)
            #expect(UIText.bedrockModelSent(config, profileRegion: "eu-west-1") == "Sent as eu.\(Self.haiku) in eu-west-1")
            config.region = "ap-northeast-1"
            #expect(UIText.bedrockModelSent(config, profileRegion: "eu-west-1") == "Sent as jp.\(Self.haiku) in ap-northeast-1")
            config.modelId = "global." + Self.haiku
            #expect(UIText.bedrockModelSent(config, profileRegion: nil) == nil)
        }
        config.modelId = "us." + Self.haiku
        UIText.$scopedLanguage.withValue("zh-Hans") {
            #expect(UIText.bedrockModelSent(config, profileRegion: nil) == "在 ap-northeast-1 实际发送 jp.\(Self.haiku)")
        }
    }

    // MARK: Requests

    func converter(region: String?, profileRegion: String?, modelId: String) -> Converter {
        var config = Config.default
        config.region = region
        config.modelId = modelId
        config.awsProfile = "test"
        let fixed = config
        return Converter(client: BedrockClient(session: GeographyRecorder.session()), loadConfig: { fixed },
                         loadCredentials: { _ in
                             AWSSharedConfig.Resolved(credentials: AWSCredentials(accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "secret"),
                                                      region: profileRegion)
                         },
                         hasAWSProfile: { _ in true })
    }

    /// The region set in the config (not the profile's): its geography's profile goes there, and the answer comes.
    @Test func theConfiguredRegionsGeography() async throws {
        GeographyRecorder.reset(serving: ["au." + Self.haiku])
        var final: ConversionUpdate?
        for try await update in converter(region: "ap-southeast-2", profileRegion: "us-east-1", modelId: "us." + Self.haiku)
            .convert("我今天有点不舒服") { final = update }
        #expect(final?.isFinal == true && final?.result.versions.isEmpty == false)
        #expect(GeographyRecorder.asked == ["ap-southeast-2 au." + Self.haiku])
    }

    /// A region with no profile of the model's (São Paulo): sent as it is, refused, and the error names both.
    @Test func refusedTheErrorNamesTheModelAndTheRegion() async throws {
        GeographyRecorder.reset(serving: [])
        do {
            for try await _ in converter(region: nil, profileRegion: "sa-east-1", modelId: "us." + Self.haiku).convert("你好") {}
            Issue.record("no error")
        } catch {
            #expect(error as? BedrockError == .modelNotInRegion(model: "us." + Self.haiku, region: "sa-east-1"))
            let english = UIText.$scopedLanguage.withValue("en") { UIText.describe(error) }
            #expect(english == "Bedrock doesn't offer us.\(Self.haiku) in sa-east-1: choose another model in Settings → AI, "
                + "or a region that offers it")
            let chinese = UIText.$scopedLanguage.withValue("zh-Hans") { UIText.describe(error) }
            #expect(chinese.contains("sa-east-1") && chinese.contains("us." + Self.haiku) && chinese.contains("设置 → AI"))
        }
        #expect(GeographyRecorder.asked == ["sa-east-1 us." + Self.haiku])
    }

    /// Another refusal is shown as Bedrock said it, not as a model missing from the region.
    @Test func otherValidationErrorsAsBedrockSaidThem() async throws {
        GeographyRecorder.reset(serving: [], message: "Malformed input request, please reformat your input and try again.")
        await #expect(throws: BedrockError.http(status: 400, type: "ValidationException",
                                                message: "Malformed input request, please reformat your input and try again.")) {
            for try await _ in converter(region: "eu-west-1", profileRegion: nil, modelId: "us." + Self.haiku).convert("你好") {}
        }
        #expect(GeographyRecorder.asked == ["eu-west-1 eu." + Self.haiku])
    }
}

/// bedrock-runtime serving only the model IDs given (`reset`), the captured stream for them; any other a 400
/// ValidationException (Bedrock's "The provided model identifier is invalid.", or `message`). Records "REGION MODEL"
/// for each request.
final class GeographyRecorder: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock(initialState: (serving: Set<String>(), message: "", asked: [String]()))

    static func reset(serving: Set<String>, message: String = "The provided model identifier is invalid.") {
        state.withLock { $0 = (serving, message, []) }
    }

    static var asked: [String] { state.withLock { $0.asked } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeographyRecorder.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, host.hasPrefix("bedrock-runtime."), request.httpMethod == "POST" else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let region = host.split(separator: ".")[1]
        let parts = url.path.split(separator: "/")
        let model = parts.count >= 2 ? String(parts[1]).removingPercentEncoding ?? String(parts[1]) : ""
        let (serves, message) = Self.state.withLock { state in
            state.asked.append("\(region) \(model)")
            return (state.serving.contains(model), state.message)
        }
        let status: Int, headers: [String: String], body: Data
        if serves, let stream = try? fixture("bedrock-converse-stream") {
            (status, headers, body) = (200, ["Content-Type": "application/vnd.amazon.eventstream"], Data(stream))
        } else {
            (status, headers, body) = (400, ["x-amzn-ErrorType": "ValidationException:http://internal.amazon.com/coral/com.amazon.bedrock/"],
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
