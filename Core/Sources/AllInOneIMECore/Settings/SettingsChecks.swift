import Foundation

// The settings' Test buttons: Test Connection (the AI provider), the web search's and the Notion link's. Each works on
// what it is given (a copy of the config, the key as kept), off whatever thread or actor shows its answer.

extension SettingsStore {
    /// Test Connection: one conversion with `config` as it is now, of a sentence in its first input language. Passed:
    /// how long it took and the first version (and the first rewrite that says something else, as the candidate panel
    /// shows them); failed: why. `loadCredentials`: Bedrock's, fetched again through the profile's whole chain (a
    /// program, STS, SSO), not the cached ones.
    public static func testConnection(_ config: Config, loadCredentials: @escaping Converter.CredentialLoader) async -> TestStatus {
        let converter = Converter(loadConfig: { config }, loadCredentials: loadCredentials)
        // In the first input language: an English-only user sees an English test.
        let sample = switch config.inputLanguages.first ?? .english {
        case .chinese: "我今天有点不舒服"
        case .english: "i dont feel so good today"
        case .french: "je me sens pas tres bien aujourdhui"
        case .korean: "오늘 몸이 좀 안 좋아요"
        case .hindi: "आज मेरी तबीयत ठीक नहीं है"
        }
        do {
            var final = ConversionResult.empty
            var elapsed: TimeInterval = 0
            for try await update in converter.convert(sample) where update.isFinal {
                final = update.result
                elapsed = update.elapsed
            }
            // Three versions with one translation language, a line each with several.
            guard let first = final.versions.first?.text ?? final.translations.first?.line.text else {
                throw BedrockError.invalidResponse(tr("没有返回结果", "no result"))
            }
            // Like the candidate panel: a rewrite that only changes punctuation or repeats a row isn't shown.
            let shown = Set(([sample] + final.versions.map(\.text) + final.translations.map(\.line.text)).map(\.wordingKey))
            let rewrite = final.rewrites.first { !shown.contains($0.line.text.wordingKey) }
                .map { "\n" + (RewriteStyle.named($0.style).map(UIText.name) ?? $0.style) + tr("：", ": ") + $0.line.text } ?? ""
            return .passed(String(format: tr("%.1f 秒：%@%@", "%.1f s: %@%@"), elapsed, first, rewrite))
        } catch {
            return .failed(UIText.describe(error))
        }
    }

    /// The web search's Test: one search for `query` with the key as it is kept. Reading the key may ask the keychain
    /// (and the login password): it is read on another thread.
    public static func testSearch(_ query: String = tr("输入法", "input method")) async -> TestStatus {
        let started = Date()
        do {
            let key = await Task.detached { WebSearch.loadKey() }.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else {
                throw WebSearch.SearchError.missingKey(variable: WebSearch.backend.keyVariables.first ?? "")
            }
            let first = try await WebSearch.search(query, key: key).first
            let shown = first.map { $0.title.isEmpty ? $0.url : $0.title } ?? ""
            return .passed(String(format: tr("%.1f 秒：%@", "%.1f s: %@"), Date().timeIntervalSince(started), shown))
        } catch {
            return .failed(UIText.describe(error))
        }
    }

    /// The Notion link's Test: `link` (else the page or database kept, `kept`) resolved with the token kept, within
    /// 10 s. Throws what went wrong (`NoteError`, …).
    public static func resolveNotion(link: String, kept: NotionTarget?, session: URLSession) async throws -> NotionTarget {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if link.isEmpty {
            guard let kept else { throw NoteError.notionNotSetUp }
            id = kept.id
        } else {
            guard let found = NotionLink.id(from: link) else { throw NoteError.notNotionLink }
            id = found
        }
        // The keychain may ask for the login password: not on the caller's thread.
        let token = await Task.detached { NotionAPI.loadToken() }.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { throw NoteError.notionNotSetUp }
        return try await NotionAPI.resolve(id, token: token, session: session)
    }

    /// What the Notion link's Test found: @note saves there from now on.
    public func useNotion(_ target: NotionTarget) {
        config.notes.notion = target
        config.notes.destination = .notion
        save()
    }
}
