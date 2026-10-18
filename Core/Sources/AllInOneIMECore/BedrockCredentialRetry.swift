import Foundation

extension BedrockError {
    /// Whether Bedrock refused the credentials as expired or no longer known: `ExpiredTokenException`,
    /// `UnrecognizedClientException`, `InvalidSignatureException` saying the token expired, or a 403 saying so.
    public var isExpiredCredentials: Bool {
        let type: String?, message: String, status: Int?
        switch self {
        case let .http(s, t, m): (status, type, message) = (s, t, m)
        case let .stream(t, m): (status, type, message) = (nil, t, m)
        case .invalidRegion, .invalidResponse: return false
        }
        let lower = message.lowercased()
        let saysExpired = lower.contains("expired") && (lower.contains("token") || lower.contains("credential") || lower.contains("security"))
        switch type {
        case "ExpiredTokenException", "ExpiredToken", "UnrecognizedClientException": return true
        case "InvalidSignatureException": return saysExpired
        default: return status == 403 && saysExpired
        }
    }
}

extension ChatClient {
    /// Bedrock with the profile's credentials (`loadCredentials`); refused as expired before any answer came, the
    /// credentials are refreshed (`Resolved.refresh`, else loaded again) and the request sent again, once.
    func bedrockStream(_ body: ConverseRequest, config: Config,
                       loadCredentials: @escaping CredentialLoader) -> AsyncThrowingStream<BedrockStreamEvent, Error> {
        let bedrock = self.bedrock
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var resolved = try await loadCredentials(config.awsProfile)
                    var retried = false
                    while true {
                        var answered = false
                        do {
                            let stream = bedrock.converseStream(body, modelId: config.modelId,
                                                                region: config.region ?? resolved.region ?? "us-east-1",
                                                                credentials: resolved.credentials, timeout: config.timeoutSeconds)
                            for try await event in stream {
                                answered = true
                                continuation.yield(event)
                            }
                            continuation.finish()
                            return
                        } catch let error as BedrockError where error.isExpiredCredentials && !answered && !retried {
                            retried = true
                            try Task.checkCancellation()
                            if let refresh = resolved.refresh {
                                resolved = try await refresh()
                            } else {
                                resolved = try await loadCredentials(config.awsProfile)
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
