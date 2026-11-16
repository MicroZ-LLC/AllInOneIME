import Foundation

/// Bedrock's geographic cross-region inference profiles. An ID with a geography's prefix ("us.anthropic.claude-…",
/// "eu.…", "jp.…") is served only when it is called from one of that geography's source regions; from any other region
/// Bedrock answers "The provided model identifier is invalid." The suggested models and the default are "us." IDs, and
/// the region a request goes to is the config's or the AWS profile's: with a profile in Ireland or Tokyo every request
/// failed. So the ID goes out with the profile of the region's own geography (`modelId(_:in:)`). Never "global.": it
/// routes to any commercial region in the world, out of the user's geography.
///
/// The source regions of each geography are those AWS lists under "Geo inference details" on the model cards, all of
/// them together (Claude Haiku 4.5, Sonnet 4, 4.5 and 4.6, Opus 4.8, Amazon Nova 2 Lite; read 2026-11):
/// https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html sends there for the profiles'
/// source regions, https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-haiku-4-5.html
/// is the default model's. A model may lack a geography's profile (Claude Sonnet 4.6 has no "in."): the request then
/// fails as it would have, and says so (`BedrockError.modelNotInRegion`).
public enum BedrockGeography {
    /// Each geography's prefix and source regions. A region in more than one (Tokyo is in "jp." and "apac.") gets the
    /// first: "jp.", "au." and "in." before "apac.", which only older models have (Claude Sonnet 4, Nova 1).
    static let geographies: [(prefix: String, regions: Set<String>)] = [
        ("jp", ["ap-northeast-1", "ap-northeast-3"]),
        ("au", ["ap-southeast-2", "ap-southeast-4", "ap-southeast-6"]),
        ("in", ["ap-south-1", "ap-south-2"]),
        // Canada's regions and GovCloud's call the US profiles (which keep GovCloud's requests in GovCloud).
        ("us", ["us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1", "ca-west-1", "us-gov-east-1", "us-gov-west-1"]),
        ("eu", ["eu-central-1", "eu-central-2", "eu-north-1", "eu-south-1", "eu-south-2", "eu-west-1", "eu-west-2", "eu-west-3",
                "il-central-1"]),
        ("apac", ["ap-northeast-1", "ap-northeast-2", "ap-northeast-3", "ap-south-1", "ap-south-2", "ap-southeast-1",
                  "ap-southeast-2"]),
    ]

    /// `modelId` as it is sent to `region`: a geography's profile that `region` can't call, with the prefix of the
    /// geography `region` is in instead ("us.anthropic.claude-haiku-4-5-…" to eu-west-1: "eu.anthropic.…"). Anything
    /// else as it is: a profile `region` can call, "global.", a model's own ID, an ARN, and any ID in a region of no
    /// geography (São Paulo, Bahrain…).
    public static func modelId(_ modelId: String, in region: String) -> String {
        guard let dot = modelId.firstIndex(of: "."),
              let own = geographies.first(where: { $0.prefix == modelId[..<dot] }), !own.regions.contains(region),
              let local = geographies.first(where: { $0.regions.contains(region) })
        else { return modelId }
        return local.prefix + modelId[dot...]
    }
}

extension Config {
    /// The region Bedrock's requests go to: the config's own, else the AWS profile's (`profileRegion`), else us-east-1.
    public func bedrockRegion(profileRegion: String?) -> String { region ?? profileRegion ?? "us-east-1" }

    /// The model ID sent to `region`: `modelId` with the profile of the region's geography (`BedrockGeography`).
    public func bedrockModelId(in region: String) -> String { BedrockGeography.modelId(modelId, in: region) }
}

extension BedrockError {
    /// Whether Bedrock refused the model ID as one it doesn't serve in the region asked: a ValidationException, "The
    /// provided model identifier is invalid." (a profile of another geography, a model not in that region, a typo).
    var isInvalidModel: Bool {
        guard case let .http(_, type, message) = self else { return false }
        return type == "ValidationException" && message.localizedCaseInsensitiveContains("model identifier is invalid")
    }
}

extension UIText {
    /// Settings → AI's line for Bedrock where the model ID sent isn't the one set (`Config.bedrockModelId`): which one
    /// goes to which region (on the Mac under the profile's status, in the settings document the model field's help).
    /// Nil where they are the same. `profileRegion`: the AWS profile's, as the region field shows it when empty.
    public static func bedrockModelSent(_ config: Config, profileRegion: String?) -> String? {
        let region = config.bedrockRegion(profileRegion: profileRegion)
        let sent = config.bedrockModelId(in: region)
        return sent == config.modelId ? nil : tr("在 \(region) 实际发送 \(sent)", "Sent as \(sent) in \(region)")
    }
}

/// A model Bedrock doesn't serve in the region, in the interface language (`UIText.describe` asks it first): not only
/// "The provided model identifier is invalid." but the model and the region it went to, and what to change. Bedrock's
/// other errors as `UIText.describe` says them.
extension BedrockError: InterfaceDescribedError {
    public var interfaceDescription: String? {
        guard case let .modelNotInRegion(model, region) = self else { return nil }
        return tr("Bedrock 在 \(region) 不提供 \(model)：在设置 → AI 里换一个模型，或换一个提供它的区域",
                  "Bedrock doesn't offer \(model) in \(region): choose another model in Settings → AI, or a region that offers it")
    }
}
