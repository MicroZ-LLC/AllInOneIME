import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for issue #179 (owner decision), written from its text: hiding sensitive information from the AI
// (`Config.redaction`) is on by default for new installs only; existing users' settings don't change; no new setting.
//
// What "an existing user's file" holds, from the history: `redaction` came with a4779610 (2026-10-14, 0.6.4), and
// `Config.encode` has written the whole object (`"enabled": false` included) ever since. So a file written by 0.6.4 or
// later says `"redaction": {"enabled": false, …}` (or true, once turned on), and only a file from before 0.6.4, or one
// written by hand, has no "redaction" key or an object without "enabled".
//
// A new install's config is what `Config.load` returns where there is no file (`Config.fresh`); `Config.default` is
// also what a file's missing keys fall back to, so these tests don't say which value it holds.
//
// The requests of the end-to-end tests go to the stubbed provider of RedactionAcceptanceTests (`LeakRig`): offline.

/// The sentences of the issue, typical of @improve and @translate, with the values in them.
struct Issue179Sample: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String
    /// The text as it may be sent.
    let sent: String
    /// The sensitive values, in the order they appear.
    let values: [String]

    var testDescription: String { name }

    static let key = "sk-EXAMPLE0123456789abcdefEXAMPLE"

    static let english = Issue179Sample(
        name: "email and phone",
        text: "Email me at jane.doe@example.com or call +1 415 555 0100 tomorrow",
        sent: "Email me at [EMAIL_1] or call [PHONE_1] tomorrow",
        values: ["jane.doe@example.com", "+1 415 555 0100"])

    static let all: [Issue179Sample] = [
        english,
        Issue179Sample(
            name: "card in Chinese",
            text: "我的卡号是 4111 1111 1111 1111，请帮我写封信",
            sent: "我的卡号是 [CARD_1]，请帮我写封信",
            values: ["4111 1111 1111 1111"]),
        Issue179Sample(
            name: "API key",
            text: "Please rotate the key \(key) before Friday, it was pasted in the channel.",
            sent: "Please rotate the key [KEY_1] before Friday, it was pasted in the channel.",
            values: [key]),
        Issue179Sample(
            name: "IP address",
            text: "The staging server is at 192.168.1.20, port 8080, since version 2.0.1.",
            sent: "The staging server is at [IP_1], port 8080, since version 2.0.1.",
            values: ["192.168.1.20"]),
        Issue179Sample(
            name: "mixed Chinese and English",
            text: "请把 invoice 发到 billing@example.com，服务器 192.168.1.20 的 token 是 \(key)，有问题打 +86 138 0013 8000",
            sent: "请把 invoice 发到 [EMAIL_1]，服务器 [IP_1] 的 token 是 [KEY_1]，有问题打 [PHONE_1]",
            values: ["billing@example.com", "192.168.1.20", key, "+86 138 0013 8000"]),
        Issue179Sample(
            name: "Chinese without spaces",
            text: "我的邮箱是jane.doe@example.com，电话13800138000。明天下午3点开会，Q3 的 roadmap 也一起看。",
            sent: "我的邮箱是[EMAIL_1]，电话[PHONE_1]。明天下午3点开会，Q3 的 roadmap 也一起看。",
            values: ["jane.doe@example.com", "13800138000"]),
    ]
}

/// A config file of its own in a folder of its own, removed after `body`. With `json` nil there is no file: a new
/// install.
private func withConfigFile<T>(_ json: String?, _ body: (URL) throws -> T) throws -> T {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue179-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("config.json")
    if let json { try Data(json.utf8).write(to: url) }
    return try body(url)
}

/// `"redaction"."enabled"` as the file at `url` says it (nil: not there).
private func enabledInFile(_ url: URL) throws -> Bool? {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    return (object?["redaction"] as? [String: Any])?["enabled"] as? Bool
}

@Suite(.serialized)
struct Issue179RedactionDefaultTests {
    /// A config file as 0.6.3 (before `redaction`) wrote it, shortened: no "redaction" key.
    static let before064 = """
        {
          "awsProfile" : "default",
          "maxTokens" : 1000,
          "modelId" : "us.anthropic.claude-haiku-4-5-20251001-v1:0",
          "provider" : "bedrock",
          "rewriteStyles" : ["润色", "简洁"],
          "temperature" : 0.3,
          "timeoutSeconds" : 15,
          "useSelection" : true
        }
        """

    // MARK: 1. A new install

    /// Spec 1: "A fresh config (no config file: Config.default or however the app builds its first config; find it)
    /// has redaction.enabled == true." The app's first config is `Config.load` with no file.
    @Test func newInstallHidesByDefault() throws {
        let config = try withConfigFile(nil) { try Config.load(from: $0) }
        #expect(config.redaction.enabled, "no config file: a new install hides sensitive information")
    }

    /// Spec 1, as above: `Config.fresh` (a new user's settings), whatever the system's languages are.
    @Test(arguments: [[], ["en-US"], ["zh-Hans-CN", "en-US"], ["ja-JP"]])
    func freshConfigHidesByDefault(_ languages: [String]) {
        #expect(Config.fresh(preferring: languages).redaction.enabled)
        #expect(Config.fresh.redaction.enabled)
    }

    /// Spec: "no new setting": a new install's hiding is the one existing switch turned on, with every detector on
    /// and no words of the user's yet, as turning it on in Settings gives.
    @Test func newInstallHidesEveryKind() throws {
        let config = try withConfigFile(nil) { try Config.load(from: $0) }
        #expect(config.redaction == RedactionSettings(enabled: true))
        #expect(config.redaction.emails && config.redaction.phones && config.redaction.cards && config.redaction.keys
            && config.redaction.ips)
        #expect(config.redaction.customWords.isEmpty)
    }

    /// Spec 1: a new install stays on once its config file exists: the first change of any other setting writes the
    /// file, and the file read again still hides.
    @Test func newInstallStaysOnOnceItsFileIsWritten() throws {
        try withConfigFile(nil) { url in
            let changed = try Config.change(at: url) { $0.menuBarIcon.toggle() }
            #expect(changed.redaction.enabled)
            #expect(FileManager.default.fileExists(atPath: url.path))
            let inFile = try enabledInFile(url)
            #expect(inFile == true, "the new install's file says so itself")
            let read = try Config.load(from: url)
            #expect(read.redaction.enabled)
        }
        try withConfigFile(nil) { url in
            let written = try Config.load(from: url).writeIfMissing(to: url)
            #expect(written)
            let inFile = try enabledInFile(url)
            #expect(inFile == true)
            let read = try Config.load(from: url)
            #expect(read.redaction.enabled)
        }
    }

    /// Spec: "no new setting": the one switch still turns it off, for a new install too, and it stays off.
    @Test func newInstallCanTurnItOff() throws {
        try withConfigFile(nil) { url in
            try Config.change(at: url) { $0.redaction.enabled = false }
            let inFile = try enabledInFile(url)
            #expect(inFile == false)
            let read = try Config.load(from: url)
            #expect(!read.redaction.enabled)
        }
    }

    /// Spec 1, end to end: with a new install's config, @improve and @translate send none of the values of "Email me
    /// at jane.doe@example.com or call +1 415 555 0100 tomorrow", and every row has them back.
    @Test(arguments: [WritingMode.improve, .translate])
    func newInstallSendsNoSensitiveValue(_ mode: WritingMode) async throws {
        let sample = Issue179Sample.english
        let rig = LeakRig(wire: .anthropic, tag: "i179new\(mode == .improve ? "i" : "t")")
        let config = rig.configure(try withConfigFile(nil) { try Config.load(from: $0) })
        rig.reply(echoLines(WritingPlan.make(mode, text: sample.text, config: config).lineTags))
        let updates = try await leakCollect(rig.converter(config).convert(sample.text, mode: mode))
        #expect(rig.requests.count == 1)
        #expect(leaked(rig.requests, sample.values).isEmpty, "\(leaked(rig.requests, sample.values))")
        let final = try #require(updates.last)
        let rows = leakRows(final.result)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0 == sample.text }, "\(rows)")
        #expect(final.hidden == sample.values.count)
    }

    // MARK: 2. A file that says it

    /// Spec 2: "A config JSON that already says "redaction": {"enabled": false} stays false; one that says true
    /// stays true."
    @Test(arguments: [false, true])
    func fileThatSaysItKeepsIt(_ enabled: Bool) throws {
        let json = #"{"redaction": {"enabled": \#(enabled)}}"#
        let decoded = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(decoded.redaction.enabled == enabled)
        try withConfigFile(json) { url in
            let read = try Config.load(from: url)
            #expect(read.redaction.enabled == enabled)
            // Another setting changed, and the file read again.
            try Config.change(at: url) { $0.menuBarIcon.toggle() }
            let inFile = try enabledInFile(url)
            #expect(inFile == enabled)
            let again = try Config.load(from: url)
            #expect(again.redaction.enabled == enabled)
        }
    }

    /// Spec 2, for the file 0.6.4 and later write: the whole config with every `redaction` field, off (an existing
    /// user who never turned it on) or on.
    @Test(arguments: [false, true])
    func fileWrittenWholeKeepsIt(_ enabled: Bool) throws {
        try withConfigFile(nil) { url in
            var config = Config.default
            config.redaction = RedactionSettings(enabled: enabled, phones: false, customWords: ["Phoenix"])
            try config.write(to: url)
            let inFile = try enabledInFile(url)
            #expect(inFile == enabled)
            let read = try Config.load(from: url)
            #expect(read.redaction == RedactionSettings(enabled: enabled, phones: false, customWords: ["Phoenix"]))
        }
    }

    // MARK: 3. An existing user's file that doesn't say it

    /// Spec 3: "A file with no "redaction" key at all must keep the OLD default (false), because that user never
    /// chose."
    @Test(arguments: ["{}", before064, #"{"provider": "anthropic", "autocomplete": true}"#])
    func fileWithoutTheKeyStaysOff(_ json: String) throws {
        let decoded = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(!decoded.redaction.enabled)
        let read = try withConfigFile(json) { try Config.load(from: $0) }
        #expect(!read.redaction.enabled, "an existing user's file without \"redaction\" stays off")
    }

    /// Spec 3: "a file with a "redaction" object lacking "enabled" also keeps false." Its other fields are read as
    /// they are.
    @Test func redactionObjectWithoutEnabledStaysOff() throws {
        let empty = try withConfigFile(#"{"redaction": {}}"#) { try Config.load(from: $0).redaction }
        #expect(empty == RedactionSettings(enabled: false))
        let read = try withConfigFile(#"{"redaction": {"emails": false, "customWords": ["Phoenix"]}}"#) {
            try Config.load(from: $0).redaction
        }
        #expect(!read.enabled)
        #expect(read == RedactionSettings(enabled: false, emails: false, customWords: ["Phoenix"]))
        let decoded = try JSONDecoder().decode(RedactionSettings.self, from: Data(#"{"ips": false}"#.utf8))
        #expect(decoded == RedactionSettings(enabled: false, ips: false))
    }

    /// Spec: "existing users' settings don't change": an existing file without the key stays off after another
    /// setting is changed (only that key is written) and after the config is written whole.
    @Test func existingFileStaysOffWhenWrittenAgain() throws {
        try withConfigFile(Self.before064) { url in
            let changed = try Config.change(at: url) { $0.menuBarIcon.toggle() }
            #expect(!changed.redaction.enabled)
            let inFile = try enabledInFile(url)
            #expect(inFile != true)
            let read = try Config.load(from: url)
            #expect(!read.redaction.enabled)
        }
        try withConfigFile(Self.before064) { url in
            try Config.load(from: url).write(to: url)
            let inFile = try enabledInFile(url)
            #expect(inFile == false)
            let read = try Config.load(from: url)
            #expect(!read.redaction.enabled)
        }
    }

    /// Spec: "existing users' settings don't change", end to end: with an existing user's file from before the
    /// setting, the sentence is sent as typed and nothing is counted as hidden.
    @Test func existingUserSendsAsTyped() async throws {
        let sample = Issue179Sample.english
        let rig = LeakRig(wire: .anthropic, tag: "i179old")
        let config = rig.configure(try withConfigFile(Self.before064) { try Config.load(from: $0) })
        rig.reply(echoLines(WritingPlan.make(.improve, text: sample.text, config: config).lineTags))
        let updates = try await leakCollect(rig.converter(config).convert(sample.text, mode: .improve))
        let request = try #require(rig.requests.first)
        #expect(sentText(request, .anthropic).contains(sample.text))
        #expect(placeholders(in: sentText(request, .anthropic)).isEmpty)
        #expect(!systemText(request).contains(Redaction.note))
        let final = try #require(updates.last)
        #expect(final.hidden == 0)
    }

    // MARK: 4. Quality, offline

    /// Spec 4: "the redacted text keeps everything else unchanged (only the sensitive spans are replaced,
    /// placeholders are short tokens that a model would keep as-is)".
    @Test(arguments: Issue179Sample.all)
    func onlyTheSensitiveSpansAreReplaced(_ sample: Issue179Sample) throws {
        var redaction = try #require(Redaction(RedactionSettings(enabled: true)))
        let sent = redaction.hide(sample.text)
        #expect(sent == sample.sent)
        for value in sample.values { #expect(!sent.contains(value), "\(value) still in \(sent)") }
        #expect(redaction.hidden.map(\.value) == sample.values)
        #expect(redaction.count == sample.values.count)
        // Short tokens: capitals, "_" and a number in square brackets, nothing a model has to translate.
        let token = try NSRegularExpression(pattern: #"^\[[A-Z]{2,5}_[0-9]{1,3}\]$"#)
        for placeholder in redaction.hidden.map(\.placeholder) {
            #expect(token.firstMatch(in: placeholder, range: NSRange(location: 0, length: placeholder.utf16.count)) != nil, "\(placeholder)")
            #expect(placeholder.count <= 10)
        }
        #expect(placeholders(in: sent) == redaction.hidden.map(\.placeholder))
        // Everything else unchanged: each placeholder swapped for its value by hand is the sentence as typed.
        var byHand = sent
        for hidden in redaction.hidden { byHand = byHand.replacingOccurrences(of: hidden.placeholder, with: hidden.value) }
        #expect(byHand == sample.text)
    }

    /// Spec 4: "redacting then restoring (the existing round-trip API …) gives back exactly the original sentence".
    @Test(arguments: Issue179Sample.all)
    func hideThenRestoreIsTheSentenceAsTyped(_ sample: Issue179Sample) throws {
        var redaction = try #require(Redaction(RedactionSettings(enabled: true)))
        let sent = redaction.hide(sample.text)
        let restored = redaction.restore(sent)
        #expect(restored == sample.text)
        #expect(!Redaction.isAltered(restored, original: sample.text))
        // A line still streaming in, cut anywhere, never shows more or other than the sentence so far.
        for end in sent.indices {
            let partial = redaction.restore(String(sent[..<end]), complete: false)
            #expect(sample.text.hasPrefix(partial), "\(sent[..<end]) -> \(partial)")
        }
    }

    /// Spec 4: a sentence with nothing sensitive is sent as typed, with hiding on.
    @Test(arguments: [
        "Let's meet at 3pm tomorrow, room 204, to review the Q3 roadmap (v2.0.1).",
        "明天下午三点开会，讨论一下第三季度的计划，大概 45 分钟。",
        "这个 PR 改了 12 个文件，帮我写个 summary，语气正式一点。",
    ])
    func ordinarySentencesAreSentAsTyped(_ text: String) throws {
        var redaction = try #require(Redaction(RedactionSettings(enabled: true)))
        #expect(redaction.hide(text) == text)
        #expect(redaction.count == 0)
        #expect(redaction.restore(text) == text)
    }

    /// Spec 4: "a model answer that reorders the placeholders or translates around them (e.g. the translated sentence
    /// containing the placeholders in another order) restores each original value at its placeholder."
    @Test func reorderedAndTranslatedAnswersRestoreEachValueAtItsPlaceholder() throws {
        var redaction = try #require(Redaction(RedactionSettings(enabled: true)))
        #expect(redaction.hide(Issue179Sample.english.text) == "Email me at [EMAIL_1] or call [PHONE_1] tomorrow")
        let (email, phone) = ("jane.doe@example.com", "+1 415 555 0100")
        let answers: [(model: String, shown: String)] = [
            ("明天请拨打 [PHONE_1]，或发邮件到 [EMAIL_1]。", "明天请拨打 \(phone)，或发邮件到 \(email)。"),
            ("明天请致电[PHONE_1]或发邮件至[EMAIL_1]", "明天请致电\(phone)或发邮件至\(email)"),
            ("明日は [PHONE_1] にお電話いただくか、[EMAIL_1] までメールをください。", "明日は \(phone) にお電話いただくか、\(email) までメールをください。"),
            ("Rufen Sie mich morgen unter [PHONE_1] an oder schreiben Sie an [EMAIL_1].",
             "Rufen Sie mich morgen unter \(phone) an oder schreiben Sie an \(email)."),
            // One used twice, one left out.
            ("[PHONE_1] is my number; again: [PHONE_1].", "\(phone) is my number; again: \(phone)."),
            ("Tomorrow, write to [EMAIL_1].", "Tomorrow, write to \(email)."),
        ]
        for answer in answers {
            let shown = redaction.restore(answer.model)
            #expect(shown == answer.shown)
            #expect(!Redaction.isAltered(shown, original: Issue179Sample.english.text))
        }
    }

    /// Spec 4, as above, with two values of one kind and four kinds in one sentence: each number keeps its own value
    /// wherever the answer puts it.
    @Test func reorderedValuesOfOneKindKeepTheirOwn() throws {
        var redaction = try #require(Redaction(RedactionSettings(enabled: true)))
        let sent = redaction.hide("Forward the contract from alice@example.com to bob@example.org today")
        #expect(sent == "Forward the contract from [EMAIL_1] to [EMAIL_2] today")
        #expect(redaction.restore("今天把合同转发给 [EMAIL_2]，发件人是 [EMAIL_1]。") == "今天把合同转发给 bob@example.org，发件人是 alice@example.com。")

        let mixed = try #require(Issue179Sample.all.first { $0.name == "mixed Chinese and English" })
        var second = try #require(Redaction(RedactionSettings(enabled: true)))
        #expect(second.hide(mixed.text) == mixed.sent)
        let answer = "For questions call [PHONE_1]. The token of server [IP_1] is [KEY_1]; send the invoice to [EMAIL_1]."
        #expect(second.restore(answer) == "For questions call +86 138 0013 8000. The token of server 192.168.1.20 is "
            + "\(Issue179Sample.key); send the invoice to billing@example.com.")
    }

    /// Spec 4, through `@translate` with a stubbed provider: the request holds the placeholders and none of the
    /// values, and a translation that puts the placeholders in another order is shown with each value in its place.
    @Test func translationThatReordersIsRestoredEndToEnd() async throws {
        let sample = Issue179Sample.english
        let rig = LeakRig(wire: .anthropic, tag: "i179order")
        var base = Config.default
        base.redaction = RedactionSettings(enabled: true)
        base.setOrder([OutputLanguage.chinese, .english])
        let config = rig.configure(base)
        let tags = WritingPlan.make(.translate, text: sample.text, config: config).lineTags
        rig.reply { _ in tags.map { "\($0): 明天请拨打 [PHONE_1]，或发邮件到 [EMAIL_1]。\n" } }
        let updates = try await leakCollect(rig.converter(config).convert(sample.text, mode: .translate))
        let request = try #require(rig.requests.first)
        #expect(leaked(rig.requests, sample.values).isEmpty, "\(leaked(rig.requests, sample.values))")
        #expect(sentText(request, .anthropic).contains(sample.sent))
        #expect(systemText(request).contains(Redaction.note))
        let final = try #require(updates.last)
        let rows = leakRows(final.result)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0 == "明天请拨打 +1 415 555 0100，或发邮件到 jane.doe@example.com。" }, "\(rows)")
        #expect(final.hidden == 2)
    }
}
