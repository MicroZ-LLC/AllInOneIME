import Foundation

/// Settings → Assistant's request fitted to the on-device model's context, which holds the instructions, the conversation,
/// the prompt, the schema the answer is held to and the tools' definitions, then the answer: 4096 tokens before macOS 27,
/// 8192 since, and the schema of every setting alone takes about 2400 of them (measured on macOS 27.2). The whole request
/// when it fits, as before; else the settings the sentence is about first (`relevance`, a look at its words), a refine's
/// latest turn, then the rest while there is room: older turns, the other settings, the other apps' current values.
/// Room is kept for the answer (`answerRoom`) and the tools' calls (`toolRoom`). Nil when the settings the sentence is
/// about don't all fit with the latest turn: `AIConfigService` sends it to the user's own provider instead, or says what
/// to do.
public struct AIConfigFit: Sendable {
    /// The settings listed.
    public var scope: AIConfigPrompt.Scope
    /// A refine's turns sent: the latest ones (each answer is the whole revised JSON, so the last one holds what the
    /// earlier instructions asked for; older turns go first).
    public var turns: [Refinement.Turn]
    /// The tools the parts in `scope` need.
    public var tools: [GuidedTool]
    /// The request as it goes (values hidden from the AI already hidden), and the schema its answer is held to.
    public var body: ConverseRequest
    public var schema: GuidedSchema
    /// Its size in tokens, without the answer: the model's count where it can tell (macOS 26.4 and later), else the
    /// estimate.
    public var tokens: Int

    /// Kept for the answer: twelve changes at most, and a note.
    public static let answerRoom = 600
    /// Kept for the tools' calls and what they return, when the request has tools.
    public static let toolRoom = 250

    /// The tokens kept free of the request: the answer's room, and the tools' with tools.
    public static func reserve(tools: Bool) -> Int { answerRoom + (tools ? toolRoom : 0) }

    // MARK: - Sizes

    /// The size of `request` with `schema` and `tools` in tokens, on the high side: the texts (`AppleModel.estimatedTokens`),
    /// a few tokens for each turn's markers, the schema as the JSON schema the framework puts into the prompt and the
    /// tools' definitions (`estimatedJSONTokens`).
    public static func estimatedTokens(_ request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) -> Int {
        let texts = [request.instructions, request.prompt] + request.examples.flatMap { [$0.prompt, $0.response] }
        return texts.map(AppleModel.estimatedTokens).reduce(0, +) + 8 * (2 * request.examples.count + 2)
            + estimatedJSONTokens(schema.jsonSchema) + tools.map { estimatedJSONTokens($0.jsonSchema) }.reduce(0, +)
    }

    /// The tokens of a schema or a tool's definition as `jsonSchema` writes it, on the high side: the framework's own
    /// rendering is longer (references, definitions), about 2.8 bytes of this one a token (measured on macOS 27.2).
    static func estimatedJSONTokens(_ json: String) -> Int { json.utf8.count * 2 / 5 + 4 }

    // MARK: - What the sentence is about

    /// The parts of the settings `texts` (the sentence, a refine's instructions) are about, by the words they use (in
    /// English, Chinese and the interface's other languages, the names of languages and styles, the apps they name),
    /// and the parts of the keys in `answers` (a refine's earlier answers, which the revised one repeats); in the order
    /// `Part.allCases` has them, the provider with AWS's. And the apps with settings of their own named there (their
    /// keys in `Config.appProfiles`): by a name the catalog has for them, their bundle ID, or their key.
    public static func relevance(_ texts: [String], answers: [String] = [], context: AIConfigPrompt.Context)
        -> (parts: [AIConfigPrompt.Part], apps: [String]) {
        let text = Words(texts.joined(separator: "\n"))
        var parts = Set<AIConfigPrompt.Part>()
        for (part, words) in Self.words where words.contains(where: text.contains) { parts.insert(part) }
        // A language named: the languages typed in, or translated into (the rules tell them apart).
        if Self.languageNames.contains(where: text.contains) { parts.formUnion([.outputLanguages, .inputLanguages]) }
        if Self.styleNames.contains(where: text.contains) { parts.insert(.rewriteStyles) }
        if text.hasRegion { parts.insert(.aws) }
        // The apps it names (their settings, or new ones).
        var named = Set<String>()
        for app in context.apps.apps where app.names.contains(where: { $0.count >= 2 && text.contains($0) }) || text.contains(app.bundleID) {
            named.insert(app.bundleID.lowercased())
            parts.insert(.apps)
        }
        var apps: [String] = []
        for key in context.config.appProfiles.keys.sorted() where named.contains(key.lowercased()) || text.contains(key) {
            apps.append(key)
        }
        if !apps.isEmpty { parts.insert(.apps) }
        // What the earlier answers changed: the revised answer has them again.
        for answer in answers {
            guard let proposal = try? AIConfig.parse(AIConfigPrompt.canonical(answer)) else { continue }
            for change in proposal.changes {
                switch change.key {
                case let .setting(setting): parts.insert(.of(setting))
                case .iCloudSync: parts.insert(.iCloudSync)
                case let .app(app, _):
                    parts.insert(.apps)
                    let lower = app.lowercased()
                    let ids = Set(context.apps.apps.filter { $0.bundleID.lowercased() == lower || $0.names.contains { $0.lowercased() == lower } }
                        .map { $0.bundleID.lowercased() })
                    for key in context.config.appProfiles.keys.sorted() where !apps.contains(key) && (key.lowercased() == lower || ids.contains(key.lowercased())) {
                        apps.append(key)
                    }
                case .forbidden: break
                }
            }
        }
        // Bedrock's settings come with the provider's: "use Bedrock", "switch to Amazon Nova" choose it.
        if parts.contains(.aws) { parts.insert(.provider) }
        return (AIConfigPrompt.Part.allCases.filter(parts.contains), apps)
    }

    /// The order the parts are added in when the sentence names none of them, and after those it names: the settings
    /// people change most first.
    static let priority: [AIConfigPrompt.Part] = [.outputLanguages, .inputLanguages, .rewriteStyles, .candidateLayout, .apps, .typing,
                                                  .provider, .privacy, .selection, .questions, .updates, .iCloudSync, .aws]

    /// The words that point to each part: English, Simplified and Traditional Chinese, Japanese, Korean, German, French,
    /// Spanish and Portuguese, lowercased. A Latin word matches at the start of a word of the text (one of three letters
    /// or fewer only as a whole word); a phrase, at the start of a word; Chinese, Japanese or Korean anywhere.
    static let words: [AIConfigPrompt.Part: [String]] = [
        .outputLanguages: ["translat", "output", "target language", "翻译", "翻譯", "译成", "譯成", "译为", "譯為", "输出", "輸出", "翻訳", "出力",
                           "번역", "출력", "übersetz", "ausgabe", "tradu", "sortie", "salida", "saída"],
        .inputLanguages: ["input", "type in", "typing language", "keyboard", "default language", "language pack", "pinyin", "hangul",
                          "输入", "輸入", "打字的语言", "拼音", "语言包", "語言包", "键盘", "鍵盤", "入力", "キーボード", "입력", "한글", "키보드",
                          "eingabe", "tastatur", "saisie", "clavier", "entrada", "teclado"],
        .rewriteStyles: ["style", "rewrite", "improve", "polish", "tone", "风格", "風格", "改写", "改寫", "语气", "語氣", "スタイル", "書き換え",
                         "文体", "스타일", "어조", "stil", "umschreib", "estilo", "reescrib", "reescrev"],
        .candidateLayout: ["candidate", "row", "rows", "column", "horizontal", "vertical", "side by side", "one under", "候选", "候選", "横排", "竖排",
                           "橫排", "豎排", "候補", "縦", "후보", "가로", "세로", "kandidat", "zeile", "spalte", "candidat", "ligne", "colonne",
                           "candidato", "fila", "columna", "linha", "coluna"],
        .typing: ["type out", "typing", "typed in", "character by character", "speed", "fast", "slow", "typo", "mistake", "like a person",
                  "human", "逐字", "打字", "上屏", "速度", "快", "慢", "错字", "錯字", "打错", "打錯", "真人", "タイピング", "タイプ", "速さ",
                  "타이핑", "속도", "오타", "tipp", "geschwindigkeit", "schnell", "langsam", "frappe", "vitesse", "rapide", "lent",
                  "escrit", "velocidad", "rápid", "lent", "digita", "velocidade"],
        .selection: ["selection", "selected", "select", "选中", "選中", "选择", "選擇", "選取", "選択", "선택", "auswahl", "markiert",
                     "sélection", "selección", "seleção", "selecion"],
        .questions: ["question", "history", "remember", "问题", "問題", "记住", "記住", "历史", "歷史", "質問", "履歴", "覚え", "질문", "기록",
                     "기억", "frage", "verlauf", "merk", "historique", "mémor", "pregunta", "historial", "record", "pergunta", "histórico", "lembr"],
        .privacy: ["hide", "hidden", "redact", "privacy", "private", "sensitive", "mask", "email", "e-mail", "phone", "card", "ip", "token",
                   "key", "隐藏", "隱藏", "敏感", "隐私", "隱私", "脱敏", "去敏", "邮箱", "郵箱", "电话", "電話", "卡号", "卡號", "密钥", "密鑰",
                   "隠", "非表示", "個人情報", "メール", "電話番号", "숨기", "숨김", "개인정보", "이메일", "전화", "verberg", "datenschutz",
                   "telefon", "masquer", "confidentialit", "téléphone", "ocult", "privacidad", "teléfono", "esconder", "privacidade"],
        .updates: ["update", "new version", "更新", "新版本", "アップデート", "업데이트", "aktualisier", "mise à jour", "actualiza", "atualiza"],
        .iCloudSync: ["icloud", "sync", "同步", "同期", "동기화", "synchron", "sincroniz"],
        .provider: ["provider", "model", "claude", "anthropic", "haiku", "sonnet", "opus", "gemini", "google", "openai", "gpt", "chatgpt",
                    "deepseek", "qwen", "kimi", "moonshot", "glm", "zhipu", "siliconflow", "openrouter", "ollama", "bedrock", "amazon",
                    "aws", "nova", "base url", "baseurl", "url", "endpoint", "apple intelligence", "on-device", "on this mac", "cloud",
                    "ai service", "服务", "服務", "模型", "亚马逊", "亞馬遜", "谷歌", "深度求索", "通义", "千问", "智谱", "月之暗面", "硅基", "本机",
                    "本機", "云", "雲", "智能", "プロバイダ", "モデル", "サービス", "アマゾン", "グーグル", "クロード", "ジェミニ", "제공", "모델",
                    "서비스", "아마존", "구글", "클로드", "제미나이", "오픈ai", "anbieter", "modell", "dienst", "fournisseur", "modèle",
                    "servic", "proveedor", "modelo", "provedor"],
        .aws: ["aws", "bedrock", "amazon", "nova", "region", "profile", "亚马逊", "亞馬遜", "区域", "區域", "地区", "地區", "アマゾン",
               "リージョン", "プロファイル", "아마존", "리전", "프로필", "profil", "región", "região"],
        .apps: ["app", "apps", "application", "program", "应用", "應用", "软件", "軟體", "軟件", "程序", "程式", "アプリ", "앱", "anwendung", "appli",
                "aplicación", "aplicativo", "programa"],
    ]

    /// The interface's languages, whose words name the languages and styles (`languageNames`, `styleNames`).
    static let interfaceLanguages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"]

    /// The names of the languages that can be typed in or translated into, in the interface's languages, lowercased.
    static let languageNames: [String] = {
        var names = Set<String>()
        for language in interfaceLanguages {
            for output in OutputLanguage.catalog { names.insert(output.name(in: language).lowercased()) }
            for input in Language.allCases { names.insert(input.name(in: language).lowercased()) }
        }
        names.formUnion(Language.allCases.flatMap { [$0.displayName, $0.englishName.lowercased()] })
        // "中文" names Chinese; "中" alone (in "中间") doesn't.
        return names.filter { $0.count >= 2 }.sorted()
    }()

    /// The rewrite styles' names, in the interface's languages, lowercased.
    static let styleNames: [String] = {
        var names = Set<String>()
        for style in RewriteStyle.catalog {
            names.insert(style.name.lowercased())
            for language in interfaceLanguages { names.insert(style.name(in: language).lowercased()) }
        }
        return names.filter { $0.count >= 2 }.sorted()
    }()

    /// A text as the words are looked for in it.
    struct Words {
        let lowered: String
        /// Its words (letters and digits), lowercased.
        let words: [String]
        /// The words joined by single spaces, with one before the first: phrases are looked for at the start of a word.
        let joined: String

        init(_ text: String) {
            lowered = text.lowercased()
            words = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            joined = " " + words.joined(separator: " ")
        }

        func contains(_ word: String) -> Bool {
            let word = word.lowercased()
            guard !word.isEmpty else { return false }
            // Chinese, Japanese, Korean (and anything else past Latin's blocks): anywhere.
            if word.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return lowered.contains(word) }
            let parts = word.split { !$0.isLetter && !$0.isNumber }
            if parts.count > 1 { return joined.contains(" " + parts.joined(separator: " ")) }
            if word.count <= 3 { return words.contains(word) }
            return words.contains { $0.hasPrefix(word) }
        }

        /// An AWS region code: "us-east-1".
        var hasRegion: Bool { lowered.range(of: #"\b[a-z]{2}(-gov)?-[a-z]+-\d\b"#, options: .regularExpression) != nil }
    }

    // MARK: - The plan

    /// The request within `budget` tokens by `measure` (the size of a request with its schema and tools): the whole of it
    /// when it fits; else `relevance`'s parts and apps with the latest turn, then older turns, the other parts and the
    /// other apps while there is room. Nil when not all the parts the sentence is about fit with the latest turn (or,
    /// when it is about none, not even one part): an answer without a setting the user asked about would leave it out
    /// of the preview unsaid, so the user's own provider gets the whole request instead. `protect` hides the values
    /// hidden from the AI (`Redaction.protect`), as the request goes.
    static func plan(_ sentence: String, turns: [Refinement.Turn], context: AIConfigPrompt.Context, tools: [GuidedTool],
                     protect: (ConverseRequest) -> ConverseRequest, budget: Int, contextSize: Int,
                     measure: (AppleModelRequest, GuidedSchema, [GuidedTool]) -> Int) -> AIConfigFit? {
        func build(_ scope: AIConfigPrompt.Scope, turns kept: Int) -> AIConfigFit {
            Self.build(sentence, turns: Array(turns.suffix(kept)), context: context, scope: scope, tools: tools, protect: protect,
                       contextSize: contextSize, measure: measure)
        }
        func fits(_ fit: AIConfigFit) -> Bool { fit.tokens <= budget - reserve(tools: !fit.tools.isEmpty) }
        let whole = build(.everything, turns: turns.count)
        if fits(whole) { return whole }

        let relevant = relevance([sentence] + turns.map(\.instruction), answers: turns.suffix(1).compactMap { $0.answer.versions.first?.text },
                                 context: context)
        let named = Set(relevant.apps)
        var scope = AIConfigPrompt.Scope(parts: [], apps: named)
        var kept = min(turns.count, 1)
        var best: AIConfigFit?
        /// `scope` with `part` when that fits.
        @discardableResult func add(_ part: AIConfigPrompt.Part) -> Bool {
            var next = scope
            next.parts.insert(part)
            let fit = build(next, turns: kept)
            guard fits(fit) else { return false }
            scope = next
            best = fit
            return true
        }
        // The settings the sentence is about with the apps it names, and the latest turn: every one of them. When it
        // names none, the first part that fits.
        for part in priority where relevant.parts.contains(part) {
            guard add(part) else { return nil }
        }
        for part in priority where best == nil { add(part) }
        guard best != nil else { return nil }
        // Then older turns, the newest first.
        while kept < turns.count {
            let fit = build(scope, turns: kept + 1)
            guard fits(fit) else { break }
            kept += 1
            best = fit
        }
        // The other parts.
        for part in priority where !scope.parts.contains(part) { add(part) }
        // The other apps' current values while there is room: all of them when they fit.
        if scope.parts.contains(.apps) {
            var all = scope
            all.apps = nil
            let fit = build(all, turns: kept)
            if fits(fit) {
                best = fit
            } else {
                for app in context.config.appProfiles.filter({ !$0.value.isEmpty }).keys.sorted() where !named.contains(app) {
                    var next = scope
                    next.apps?.insert(app)
                    let fit = build(next, turns: kept)
                    guard fits(fit) else { break }
                    scope = next
                    best = fit
                }
            }
        }
        return best
    }

    /// The request for `sentence` with `turns` and the settings in `scope`, its size by `measure`.
    static func build(_ sentence: String, turns: [Refinement.Turn], context: AIConfigPrompt.Context, scope: AIConfigPrompt.Scope,
                      tools: [GuidedTool], protect: (ConverseRequest) -> ConverseRequest, contextSize: Int,
                      measure: (AppleModelRequest, GuidedSchema, [GuidedTool]) -> Int) -> AIConfigFit {
        let body = protect(AIConfigPrompt.request(sentence, context: context, turns: turns, compact: true, scope: scope))
        let schema = AIConfigPrompt.schema(context, scope: scope)
        let needed = Self.tools(tools, for: scope)
        let apple = AppleModel.request(from: body, maxTokens: body.inferenceConfig.maxTokens ?? context.config.maxTokens, contextSize: contextSize)
        return AIConfigFit(scope: scope, turns: turns, tools: needed, body: body, schema: schema, tokens: measure(apple, schema, needed))
    }

    /// The tools the parts in `scope` need: apps looked up for an app's settings, the AWS profiles for Bedrock's, the
    /// language packs for the input languages.
    static func tools(_ tools: [GuidedTool], for scope: AIConfigPrompt.Scope) -> [GuidedTool] {
        tools.filter { tool in
            switch tool.name {
            case "findApps": return scope.parts.contains(.apps)
            case "awsProfiles": return scope.parts.contains(.aws)
            case "languagePacks": return scope.parts.contains(.inputLanguages)
            default: return true
            }
        }
    }
}

extension GuidedSchema {
    /// The schema as JSON schema, about as the framework writes it into the prompt (for its size: `AIConfigFit`).
    var jsonSchema: String {
        func quoted(_ text: String) -> String { AIConfig.JSONValue.string(text).json }
        switch self {
        case let .object(name, properties):
            let fields = properties.map { property -> String in
                let inner = property.schema.jsonSchema
                let described = property.description.map { "{\"description\":\(quoted($0)),\(inner.dropFirst())" } ?? inner
                return quoted(property.name) + ":" + described
            }
            let names = properties.map { quoted($0.name) }.joined(separator: ",")
            let required = properties.filter { !$0.optional }.map { quoted($0.name) }.joined(separator: ",")
            return "{\"title\":\(quoted(name)),\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\(fields.joined(separator: ","))},"
                + "\"required\":[\(required)],\"x-order\":[\(names)]}"
        case let .choice(name, choices):
            return "{\"title\":\(quoted(name)),\"anyOf\":[\(choices.map(\.jsonSchema).joined(separator: ","))]}"
        case let .strings(_, values):
            return "{\"type\":\"string\",\"enum\":[\(values.map(quoted).joined(separator: ","))]}"
        case let .array(item, min, max):
            return "{\"type\":\"array\",\"items\":\(item.jsonSchema)" + (min.map { ",\"minItems\":\($0)" } ?? "")
                + (max.map { ",\"maxItems\":\($0)" } ?? "") + "}"
        case .string: return "{\"type\":\"string\"}"
        case .bool: return "{\"type\":\"boolean\"}"
        case let .number(min, max): return "{\"type\":\"number\",\"minimum\":\(min),\"maximum\":\(max)}"
        case let .optional(inner): return "{\"title\":\"Optional\",\"anyOf\":[\(inner.jsonSchema),{\"type\":\"null\"}]}"
        }
    }
}

extension GuidedTool {
    /// The tool's definition as JSON, about as the framework gives it to the model (for its size: `AIConfigFit`).
    var jsonSchema: String {
        let arguments = GuidedSchema.object(name: name + "Arguments", properties: arguments.map {
            GuidedSchema.Property(name: $0.name, schema: .string, description: $0.description)
        })
        return "{\"type\":\"function\",\"function\":{\"name\":\(AIConfig.JSONValue.string(name).json),"
            + "\"description\":\(AIConfig.JSONValue.string(description).json),\"parameters\":\(arguments.jsonSchema)}}"
    }
}
