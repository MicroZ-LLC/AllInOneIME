import Foundation
import os
import Testing
@testable import AllInOneIMECore

struct RedactionTests {
    let on = RedactionSettings(enabled: true)

    /// What `settings` finds in `text`, as (kind, value).
    func found(_ text: String, _ settings: RedactionSettings? = nil) -> [String] {
        Redaction.find(text, settings: settings ?? on).map { "\($0.kind.rawValue) " + (text as NSString).substring(with: $0.range) }
    }

    // MARK: Detectors

    @Test func emails() {
        #expect(found("write to bob.tester+x@mail.example.co.uk, thanks") == ["EMAIL bob.tester+x@mail.example.co.uk"])
        #expect(found("我的邮箱是zhang_san@qq.com。") == ["EMAIL zhang_san@qq.com"])
        // URLs, handles and commands are not emails.
        #expect(found("see https://example.com/path?q=1 and https://medium.com/@bob/post") == [])
        #expect(found("@improve this, cc @bob, name@localhost") == [])
    }

    @Test func phones() {
        for phone in ["+1 (555) 123-4567", "+44 20 7946 0958", "+8613800138000", "+86 138 0013 8000", "(555) 123-4567",
                      "555-123-4567", "555.123.4567", "13800138000", "138 0013 8000", "010-12345678", "020 7946 0958"] {
            #expect(found("call \(phone) today") == ["PHONE \(phone)"], "\(phone)")
        }
        #expect(found("电话13800138000找我") == ["PHONE 13800138000"])
        // Dates, times, versions, order and plain numbers are not phone numbers.
        for text in ["on 2024-10-14 at 12:30:45", "10/14/2024", "version 1.2.3 and v2.0.1", "order #12345678",
                     "order 2024101412", "it costs 1234567", "pi is 3.14159", "1,234,567 users", "port 8080",
                     "ISBN 978-3-16-148410-0", "build 20241014.1", "我们10月14日开会，预算1,200,000元，共12345人"] {
            #expect(found(text) == [], "\(text)")
        }
    }

    @Test func cards() {
        #expect(found("card 4111 1111 1111 1111 exp 12/27") == ["CARD 4111 1111 1111 1111"])
        #expect(found("amex 3782-822463-10005") == ["CARD 3782-822463-10005"])
        #expect(found("5555555555554444") == ["CARD 5555555555554444"])
        // The Luhn check fails, or no card starts so.
        #expect(found("card 4111 1111 1111 1112") == [])
        #expect(found("tracking 1234567890123456") == [])
    }

    @Test func keys() {
        let keys = ["sk-\u{61}nt-api03-AbC9xYz_12345678abcdEFGH", "sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6", "AK\u{49}AIOSFODNN7EXAMPLE",
                    "gh\u{70}_1234567890abcdefghijABCDEFGHIJ123456", "xo\u{78}b-1234567890-abcdefghij",
                    "AI\u{7A}aSyA1234567890abcdefghijklmnopqrstuv", "ey\u{4A}hbGciOiJIUzI1NiJ9.ey\u{4A}zdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"]
        for key in keys { #expect(found("key: \(key) ok") == ["KEY \(key)"], "\(key)") }
        // Long random strings: base64, hex, a UUID.
        #expect(found("token Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2Rl") == ["KEY Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2Rl"])
        #expect(found("secret 3f2a9c8b7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a") == ["KEY 3f2a9c8b7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a"])
        #expect(found("id 550e8400-e29b-41d4-a716-446655440000") == ["KEY 550e8400-e29b-41d4-a716-446655440000"])
        // Words joined are not keys; nor is sk- before words.
        for text in ["branch my-feature-branch-2024-10-14", "call very_long_function_name_v2", "QuarterlyBusinessReview2024Q3",
                     "use sk-learn-is-a-python-library", "internationalization_and_localization",
                     "open /Users/imac/workspace/AllInOneIME-custom-commands/README.zh-CN.md"] {
            #expect(found(text) == [], "\(text)")
        }
    }

    @Test func ips() {
        #expect(found("server 192.168.1.20 is down") == ["IP 192.168.1.20"])
        #expect(found("服务器10.0.0.1挂了") == ["IP 10.0.0.1"])
        #expect(found("ping 2001:db8::8a2e:370:7334 and fe80::1") == ["IP 2001:db8::8a2e:370:7334", "IP fe80::1"])
        for text in ["version 1.2.3", "v1.2.3.4", "999.1.1.1", "at 12:30:45", "std::vector", "::1", "10.0.19041.1"] {
            #expect(found(text) == [], "\(text)")
        }
    }

    @Test func customWordsAndToggles() {
        var settings = on
        settings.customWords = ["Phoenix", "张三", "Project X"]
        #expect(found("Phoenix ships; ask 张三 about project x, not Phoenixes", settings)
                == ["ITEM Phoenix", "ITEM 张三", "ITEM project x"])
        // An email over a word inside it: the longer wins, nothing of it is left.
        settings.customWords = ["bob"]
        #expect(found("bob: bob@acme.com", settings) == ["ITEM bob", "EMAIL bob@acme.com"])
        // Each detector its own switch.
        settings = on
        settings.emails = false
        settings.phones = false
        #expect(found("bob@acme.com 555-123-4567 10.0.0.1", settings) == ["IP 10.0.0.1"])
        #expect(RedactionSettings.words(from: "Phoenix, 张三，Project X、Phoenix;\nAtlas ") == ["Phoenix", "张三", "Project X", "Atlas"])
        #expect(Redaction(RedactionSettings()) == nil)  // off by default
    }

    // MARK: Hiding and restoring

    @Test func samePlaceholderForTheSameValue() throws {
        var r = try #require(Redaction(on))
        let sent = r.hide("mail bob@acme.com or amy@acme.com; again bob@acme.com, call 555-123-4567")
        #expect(sent == "mail [EMAIL_1] or [EMAIL_2]; again [EMAIL_1], call [PHONE_1]")
        // Numbering goes on across texts of one request.
        #expect(r.hide("cc amy@acme.com and joe@acme.com") == "cc [EMAIL_2] and [EMAIL_3]")
        #expect(r.count == 4)
        #expect(!sent.contains("@acme.com") && !sent.contains("555"))
    }

    @Test func roundTripAcrossRows() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("我的邮箱 bob@acme.com，电话 13800138000")
        let model = ConversionResult(
            versions: [CandidateLine("My email is [EMAIL_1] and my phone is [PHONE_1]."),
                       CandidateLine("Email me at [EMAIL_1] or call [PHONE_1]."),
                       CandidateLine("Reach me at [PHONE_1].")],
            translations: [Translation(language: OutputLanguage("ja"), line: CandidateLine("メールは[EMAIL_1]です"))],
            rewrites: [Rewrite(style: "简洁", line: CandidateLine("邮箱 [EMAIL_1]，电话 [PHONE_1]"))])
        let back = r.restore(model)
        #expect(back.versions.map(\.text) == ["My email is bob@acme.com and my phone is 13800138000.",
                                              "Email me at bob@acme.com or call 13800138000.", "Reach me at 13800138000."])
        #expect(back.translations.first?.line.text == "メールはbob@acme.comです")
        #expect(back.rewrites.first?.line.text == "邮箱 bob@acme.com，电话 13800138000")
        #expect(!([back.versions.map(\.text), [back.rewrites[0].line.text]].joined().contains(where: Redaction.isAltered)))
    }

    @Test func toleratesWhatTheModelDoesToPlaceholders() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("bob@acme.com 555-123-4567 sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6")
        let cases: [(String, String)] = [
            ("[ email_1 ]", "bob@acme.com"), ("[Email 1]", "bob@acme.com"), ("EMAIL_1", "bob@acme.com"),
            ("【邮箱_1】", "bob@acme.com"), ("[电子邮件_1]", "bob@acme.com"), ("(PHONE_1)", "555-123-4567"),
            ("［电话 1］", "555-123-4567"), ("[TOKEN_1]", "sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6"), ("[e-mail-1]", "bob@acme.com"),
            // Repeated: each one back.
            ("[EMAIL_1], [EMAIL_1]", "bob@acme.com, bob@acme.com"),
        ]
        for (model, real) in cases {
            #expect(r.restore("x \(model) y") == "x \(real) y", "\(model)")
        }
        // Dropped: nothing to put back, nothing wrong.
        #expect(r.restore("Call me.") == "Call me." && !Redaction.isAltered("Call me."))
        // Words in brackets are left alone.
        #expect(r.restore("see (item 1) and [Note 1]") == "see (item 1) and [Note 1]")
        #expect(!Redaction.isAltered("see (item 1) and [Note 1]"))
    }

    @Test func alteredPlaceholdersStayAndAreMarked() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("bob@acme.com")
        // Another number, a kind that matches nothing, a word not known with a number several have.
        for altered in ["[EMAIL_2]", "[PHONE_1]", "PHONE_1", "[CORREO_7]", "[DATO_2]"] {
            let back = r.restore("write to \(altered)")
            #expect(back == "write to \(altered)" && Redaction.isAltered(back), "\(altered)")
        }
        // A kind in a language not known here, unique by its number: put back.
        #expect(r.restore("[DATO_1]") == "bob@acme.com")
        _ = r.hide("555-123-4567")
        #expect(r.restore("[DATO_1]") == "[DATO_1]")  // EMAIL_1 or PHONE_1: can't tell
    }

    @Test func streamingLinesHideAHalfPlaceholder() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("bob@acme.com")
        #expect(r.restore("Write to [EMA", complete: false) == "Write to ")
        #expect(r.restore("Write to [EMAIL_1] to", complete: false) == "Write to bob@acme.com to")
        let line = r.restore(ConversionResult(versions: [CandidateLine("Mail [EMAIL", isComplete: false)]))
        #expect(line.versions[0].text == "Mail " && !line.versions[0].isComplete)
    }

    @Test func jargonEntriesWithHiddenValuesAreLeftOut() throws {
        var settings = on
        settings.customWords = ["Phoenix"]
        var r = try #require(Redaction(settings))
        _ = r.hide("ask bob@acme.com")
        #expect(r.allows(JargonEntry(term: "bandwidth", meaning: "time and energy")))
        #expect(!r.allows(JargonEntry(term: "Phoenix", meaning: "the Q3 project")))
        #expect(!r.allows(JargonEntry(term: "owner", meaning: "carol@acme.com")))
        #expect(!r.allows(JargonEntry(term: "PoC", meaning: "ask bob@acme.com")))
    }

    // MARK: Requests

    @Test func requestsWithoutHiddenValuesAreTheSame() throws {
        var config = Config.default
        config.rewriteStyles = ["润色", "简洁", "黑话"]
        let jargon = [JargonEntry(term: "bandwidth", meaning: "time and energy")]
        var chinese = config
        chinese.setOrder([OutputLanguage.chinese, .english])
        for c in [config, chinese] {
            for input in ["我今天有点不舒服", "this bug is blocker, your team need fix it asap", "辛苦了 thanks 2024-10-14 v1.2.3"] {
                for mode in [WritingMode.both, .improve, .translate] {
                    var r = try #require(Redaction(on))
                    let sent = r.hide(input)
                    let plain = Prompt.request(for: input, mode: mode, config: c, jargon: jargon)
                    let protected = r.protect(plain, sent: sent)
                    #expect(sent == input && protected == plain)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    #expect(try encoder.encode(protected) == encoder.encode(plain))
                }
            }
        }
        let question = Prompt.commandRequest(.question, input: "what is a monad", config: config)
        var r = try #require(Redaction(on))
        #expect(r.protect(question, sent: r.hide("what is a monad")) == question)
    }

    @Test func protectedRequestsHoldNoRealValue() throws {
        var settings = on
        settings.customWords = ["Phoenix"]
        var r = try #require(Redaction(settings))
        let input = "Phoenix launch: mail bob@acme.com, key sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6"
        let sent = r.hide(input)
        var config = Config.default
        config.rewriteStyles = ["简洁"]
        let request = r.protect(Prompt.request(for: input, mode: .improve, config: config), sent: sent)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        for value in ["Phoenix", "bob@acme.com", "sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6"] { #expect(!json.contains(value)) }
        #expect(request.messages.last?.content.first?.text == "[ITEM_1] launch: mail [EMAIL_1], key [KEY_1]")
        #expect(request.system.last?.text.hasSuffix("\n\n" + Redaction.note) == true)
        #expect(Prompt.request(for: input, mode: .improve, config: config).system.last?.text.contains("[EMAIL_1]") == false)
    }

    @Test func settingsDecodeWithDefaultsAndRoundTrip() throws {
        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"redaction": {"enabled": true, "phones": false}}"#.utf8))
        #expect(partial.redaction == RedactionSettings(enabled: true, phones: false))
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).redaction == RedactionSettings())
        var config = Config.default
        config.redaction = RedactionSettings(enabled: true, keys: false, customWords: ["Phoenix"])
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)) == config)
    }

    @Test func issueReportSaysOnlyWhetherItIsOn() {
        var config = Config.default
        config.redaction = RedactionSettings(enabled: true, customWords: ["Phoenix"])
        let report = IssueReport(title: "x", diagnostics: .init(config: config, macOS: "26.1", architecture: "arm64",
                                                                 interfaceLanguage: "en", languagePacks: [], plugins: 0, extensions: 0))
        #expect(report.lines.contains("Hide sensitive info: on"))
        #expect(!report.url.absoluteString.contains("Phoenix"))
        config.redaction.enabled = false
        #expect(IssueReport.Diagnostics(config: config, macOS: "26.1", architecture: "arm64", interfaceLanguage: "en",
                                        languagePacks: [], plugins: 0, extensions: 0).redaction == false)
    }

    // MARK: Through the converter

    /// The request's body as sent (a URL protocol may hand it over as a stream).
    static func body(_ request: URLRequest?) -> String {
        guard let request else { return "" }
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A Claude API answer streaming `text`, cut in two deltas mid-placeholder.
    static func claudeAnswer(_ text: String) -> Data {
        let cut = text.index(text.startIndex, offsetBy: text.count / 2)
        func delta(_ s: String) -> String {
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "text_delta", "text": s]), as: UTF8.self)
            return #"data: {"type":"content_block_delta","index":0,"delta":"# + json + "}\n\n"
        }
        return Data((delta(String(text[..<cut])) + delta(String(text[cut...]))
            + #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"# + "\n\n").utf8)
    }

    func converter(host: String, redaction: RedactionSettings, styles: [String] = [], jargon: [JargonEntry] = [],
                   commands: [CustomCommand] = []) -> Converter {
        var config = Config.default
        config.provider = .anthropic
        config.anthropic.baseURL = "https://\(host)"
        config.rewriteStyles = styles
        config.redaction = redaction
        config.customCommands = commands
        let fixed = config
        return Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                         loadKey: { _, _ in "sk-test" }, loadJargon: { _ in jargon })
    }

    @Test func converterNeverSendsTheRealValues() async throws {
        let host = "redact.test"
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [
            Self.claudeAnswer("EN: Please email [EMAIL_1] or call [PHONE_1].\nEN: Reach [ Email_1 ] at [PHONE_1].\n"
                + "EN: Contact me at [EMAIL_2].\nSTYLE_JARGON: Ping [邮箱_1] re [ITEM_1].\n")]))
        var settings = on
        settings.customWords = ["Phoenix"]
        let converter = converter(host: host, redaction: settings, styles: ["黑话"],
                                  jargon: [JargonEntry(term: "bandwidth"), JargonEntry(term: "Phoenix", meaning: "the launch"),
                                           JargonEntry(term: "owner", meaning: "carol@acme.com")])
        let input = "Phoenix: email bob@acme.com or call +1 (555) 123-4567, bob@acme.com again"
        var updates: [ConversionUpdate] = []
        for try await update in converter.convert(input, mode: .improve) { updates.append(update) }
        let body = Self.body(StubURLProtocol.lastRequest(host: host))
        #expect(body.contains("[EMAIL_1]") && body.contains("[PHONE_1]") && body.contains("[ITEM_1]"))
        for real in ["bob@acme.com", "555", "Phoenix", "carol@acme.com"] { #expect(!body.contains(real), "\(real) sent") }
        #expect(body.contains("bandwidth"))  // the rest of the jargon list goes
        let final = try #require(updates.last)
        #expect(final.isFinal && final.hidden == 3)
        #expect(final.result.versions.map(\.text) == ["Please email bob@acme.com or call +1 (555) 123-4567.",
                                                      "Reach bob@acme.com at +1 (555) 123-4567.", "Contact me at [EMAIL_2]."])
        #expect(final.result.rewrites.first?.line.text == "Ping bob@acme.com re Phoenix.")
        #expect(final.result.versions.map(\.text).map(Redaction.isAltered) == [false, false, true])
        // No update while streaming shows a placeholder or a part of one.
        for update in updates {
            for line in update.result.versions where !line.isComplete { #expect(!line.text.contains("[")) }
        }
    }

    @Test func converterCommandsHideTheTextAndTheirOwnPrompt() async throws {
        let host = "redact-command.test"
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [
            Self.claudeAnswer("Hi [ITEM_1], your server [IP_1] is fine. — sent from [EMAIL_1]")]))
        var settings = on
        settings.customWords = ["Carol"]
        let sign = CustomCommand(name: "sign", type: .prompt, prompt: "Reply politely and sign as ops@acme.com.")
        let converter = converter(host: host, redaction: settings, commands: [sign])
        let command = Command(name: "sign", kind: .generate, custom: sign)
        var final: ConversionUpdate?
        for try await update in converter.generate(command, input: "Carol asks if 10.0.0.12 is up") where update.isFinal { final = update }
        let body = Self.body(StubURLProtocol.lastRequest(host: host))
        for real in ["Carol", "10.0.0.12", "ops@acme.com"] { #expect(!body.contains(real), "\(real) sent") }
        #expect(body.contains("[IP_1]") && body.contains("sign as [EMAIL_1]") && body.contains(Redaction.note.prefix(40)))
        #expect(final?.hidden == 3)
        #expect(final?.result.versions.first?.text == "Hi Carol, your server 10.0.0.12 is fine. — sent from ops@acme.com")
    }

    @Test func converterWithoutHiddenValuesSendsTheSameBytes() async throws {
        var bodies: [String] = []
        for (index, redaction) in [RedactionSettings(), on].enumerated() {
            let host = "redact-same-\(index).test"
            StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                                                       chunks: [Self.claudeAnswer("EN: Thanks a lot.\n")]))
            let converter = converter(host: host, redaction: redaction, styles: ["简洁", "黑话"], jargon: [JargonEntry(term: "LGTM")])
            var final: ConversionUpdate?
            for try await update in converter.convert("辛苦了，明天 10:30 见") where update.isFinal { final = update }
            #expect(final?.hidden == 0)
            bodies.append(Self.body(StubURLProtocol.lastRequest(host: host)))
        }
        #expect(!bodies[0].isEmpty && bodies[0] == bodies[1])
        #expect(!bodies[1].contains("placeholder"))
    }
}
