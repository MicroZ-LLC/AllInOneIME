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
        #expect(!([back.versions.map(\.text), [back.rewrites[0].line.text]].joined().contains(where: { Redaction.isAltered($0) })))
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
        // A kind not ours (a language not known here) is never put back, even with the only number issued.
        #expect(r.restore("[DATO_1]") == "[DATO_1]" && Redaction.isAltered("[DATO_1]"))
    }

    // MARK: Fixes from the acceptance tests

    @Test func awsSecretsAndBase64Tokens() {
        for key in ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY", "\u{6A}e7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY",
                    "dGhpcyBpcyBhIHNlY3JldCB0b2tlbg+/aGVsbG8=", "Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2Rl=="] {
            #expect(found("aws_secret_access_key = \(key)") == ["KEY \(key)"], "\(key)")
        }
        // Paths and links are not keys.
        for text in ["open /Users/imac/workspace/AllInOneIME-custom-commands/Sources/AllInOneIMECore",
                     "see github.com/MicroZ-LLC/AllInOneIME/issues/new", "getUserAccountSettingsForCurrentSessionHandler",
                     "a/very/long/path/to/some/deeply/nested/folder"] {
            #expect(found(text) == [], "\(text)")
        }
    }

    @Test func fullWidthFormsAreFoundAndPutBackAsTyped() throws {
        var settings = on
        settings.customWords = ["Phoenix", "Café"]
        #expect(found("邮箱 zhang＠example.com，手机１３８００１３８０００", settings)
                == ["EMAIL zhang＠example.com", "PHONE １３８００１３８０００"])
        #expect(found("卡 ４１１１ １１１１ １１１１ １１１１，ＩＰ １９２．１６８．１．２０", settings)
                == ["CARD ４１１１ １１１１ １１１１ １１１１", "IP １９２．１６８．１．２０"])
        #expect(found("ｓｋ－ｐｒｏｊ－４ｆ９Ｑｘ２ＬｍＮ８ｐＲ７ｔＶ１ｗＺ３ｙＢ６ about Ｐｈｏｅｎｉｘ", settings)
                == ["KEY ｓｋ－ｐｒｏｊ－４ｆ９Ｑｘ２ＬｍＮ８ｐＲ７ｔＶ１ｗＺ３ｙＢ６", "ITEM Ｐｈｏｅｎｉｘ"])
        // Decomposed accents and any case.
        #expect(found("at the CAFE\u{301} and cafe\u{301}", settings) == ["ITEM CAFE\u{301}", "ITEM cafe\u{301}"])
        var r = try #require(Redaction(settings))
        let sent = r.hide("mail zhang＠example.com about Ｐｈｏｅｎｉｘ")
        #expect(sent == "mail [EMAIL_1] about [ITEM_1]")
        #expect(r.restore("Write to [EMAIL_1] re [ITEM_1].") == "Write to zhang＠example.com re Ｐｈｏｅｎｉｘ.")
    }

    @Test func commandPromptValuesAreAlwaysReplaced() throws {
        var r = try #require(Redaction(on))
        let prompt = "call 555-123-4567x89 or mail help@corp-secret.com_ops."
        let hidden = r.hide(["fix this", prompt])
        #expect(hidden[1] == "call [PHONE_1]x89 or mail [EMAIL_1]_ops.")
        let request = r.protect(Prompt.commandRequest(Command(name: "c", kind: .generate,
                                                              custom: CustomCommand(name: "c", type: .prompt, prompt: prompt)),
                                                      input: "fix this", config: .default), sent: hidden[0])
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("555-123") && !json.contains("corp-secret") && json.contains("[PHONE_1]x89"))
        // Whatever `find` finds, `scrub` replaces.
        let text = "ring 555-123-4567x89, write help@corp-secret.com_ops"
        #expect(Redaction.find(text, settings: on).count == 2 && !r.scrub(text).contains("555") && !r.scrub(text).contains("corp-secret"))
    }

    @Test func internationalPhonesWithShortGroups() {
        for phone in ["+81 3-1234-5678", "+33 1 23 45 67 89", "+33 6 12 34 56 78", "+49 30 123456", "+1 (555) 123-4567"] {
            #expect(found("tel \(phone) ok") == ["PHONE \(phone)"], "\(phone)")
        }
        for text in ["on 2024-10-14 at 10:30", "v1.2.3", "costs +5 USD", "+1 2 3", "order 12 3 45 6", "score +3 1 2 4"] {
            #expect(found(text) == [], "\(text)")
        }
    }

    @Test func valuesBrokenByALineBreak() {
        var settings = on
        settings.customWords = ["Project Atlas"]
        #expect(found("card 4111 1111\n1111 1111 ok", settings) == ["CARD 4111 1111\n1111 1111"])
        #expect(found("手机 138 0013\n8000", settings) == ["PHONE 138 0013\n8000"])
        #expect(found("call 555-123\n  4567", settings) == ["PHONE 555-123\n  4567"])
        #expect(found("about Project\nAtlas and project   atlas", settings) == ["ITEM Project\nAtlas", "ITEM project   atlas"])
        // Not across two line breaks.
        #expect(found("4111\n1111\n1111 1111") == [])
    }

    @Test func theUsersOwnPlaceholderShapedWordsAreNeverReplaced() throws {
        var r = try #require(Redaction(on))
        let input = "Why does ip_1 = '10.0.0.1' and ip_2 = '10.0.0.2' fail?"
        let sent = r.hide(input)
        // ip_1 and ip_2 are the user's: the addresses get other numbers.
        #expect(sent == "Why does ip_1 = '[IP_3]' and ip_2 = '[IP_4]' fail?")
        #expect(r.restore("Because ip_1 is [IP_3] and ip_2 is [IP_4].") == "Because ip_1 is 10.0.0.1 and ip_2 is 10.0.0.2.")
        #expect(r.restore("IP_1 and [IP_2]") == "IP_1 and [IP_2]")
        #expect(!Redaction.isAltered("Because ip_1 is 10.0.0.1", original: input))

        var settings = on
        settings.customWords = ["Phoenix"]
        var w = try #require(Redaction(settings))
        #expect(w.hide("See [Item 1] about Phoenix") == "See [Item 1] about [ITEM_2]")
        #expect(w.restore("See [Item 1] about [ITEM_2]") == "See [Item 1] about Phoenix")
        // A label not ours, or a number not issued, is never put back.
        #expect(w.restore("[DATO_2], [ITEM_1], ITEM_3") == "[DATO_2], [ITEM_1], ITEM_3")
        // The literal placeholder the user typed: the email gets another.
        var e = try #require(Redaction(on))
        #expect(e.hide("replace [EMAIL_1] with bob@acme.com") == "replace [EMAIL_1] with [EMAIL_2]")
        #expect(e.restore("Replace [EMAIL_1] with [EMAIL_2].") == "Replace [EMAIL_1] with bob@acme.com.")
    }

    @Test func streamingHoldsBackPartialPlaceholders() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("a@acme.com b@acme.com c@acme.com d@acme.com e@acme.com f@acme.com g@acme.com h@acme.com i@acme.com j@acme.com")
        let final = "Mail [EMAIL_10] and EMAIL_1 (EMAIL_2) now."
        var shown: [String] = []
        for end in 1...final.count {
            let partial = String(final.prefix(end))
            shown.append(r.restore(partial, complete: end == final.count))
        }
        #expect(shown.last == "Mail j@acme.com and a@acme.com b@acme.com now.")  // "(EMAIL_2)": brackets changed
        for text in shown.dropLast() {
            #expect(!text.contains("[") && !text.contains("(E") && !text.uppercased().contains("EMAI"), "\(text)")
            // Never the value of [EMAIL_1] while [EMAIL_10] comes in.
            #expect(!(text.hasPrefix("Mail a@acme.com")), "\(text)")
        }
        #expect(r.restore("Write to [EMAIL_1", complete: false) == "Write to ")
        #expect(r.restore("Write to (EMAIL_", complete: false) == "Write to ")
        #expect(r.restore("Write to EMAI", complete: false) == "Write to ")
        #expect(r.restore("Write to [", complete: false) == "Write to ")
        #expect(r.restore("Write to [EMAIL_1", complete: true) == "Write to [EMAIL_1")  // the final text is as written
    }

    @Test func numberedInOrderOfAppearance() throws {
        var r = try #require(Redaction(on))
        #expect(r.hide("first a@acme.com, then b@acme.com, then c@acme.com, a@acme.com")
                == "first [EMAIL_1], then [EMAIL_2], then [EMAIL_3], [EMAIL_1]")
        #expect(r.hidden.map(\.value) == ["a@acme.com", "b@acme.com", "c@acme.com"])
    }

    // MARK: Round 2

    @Test func emailsAfterASlash() {
        #expect(found("cc: support@corp.com/sales@corp.com") == ["EMAIL support@corp.com", "EMAIL sales@corp.com"])
        #expect(found("Email/zhang@example.com") == ["EMAIL zhang@example.com"])
        #expect(found("13800138000/zhang@example.com") == ["PHONE 13800138000", "EMAIL zhang@example.com"])
        #expect(found("电话／zhang@example.com") == ["EMAIL zhang@example.com"])
        #expect(found("see https://a.example.com/team/bob@corp.com") == ["EMAIL bob@corp.com"])
        // Still skipped: a URL's user right after the scheme, a git remote.
        #expect(found("https://user@example.com/x and git@github.com:org/repo.git") == [])
    }

    @Test func unclosedPlaceholdersInTheFinalText() throws {
        var r = try #require(Redaction(on))
        _ = r.hide("bob@acme.com")
        for text in ["mail [EMAIL_1", "mail [EMAIL_1 today", "mail (EMAIL_1", "mail [EMAIL_1, thanks", "mail [ email_1."] {
            let back = r.restore(text)
            #expect(back.contains("bob@acme.com") && !back.contains("[") && !back.contains("(") && !Redaction.isAltered(back), "\(text) → \(back)")
        }
        // Not ours, not issued, or its digits the start of another number: left, and marked.
        var many = try #require(Redaction(on))
        _ = many.hide((1...10).map { "u\($0)@acme.com" }.joined(separator: " "))
        for text in ["mail [EMAIL_1", "mail [EMAIL_12 today", "mail [PHONE_1", "mail [DATO_1 ok"] {
            let back = many.restore(text)
            #expect(back == text && Redaction.isAltered(back), "\(text) → \(back)")
        }
        #expect(many.restore("mail [EMAIL_10") == "mail u10@acme.com")
        // The user's own text holding it as written: neither put back nor marked.
        #expect(!Redaction.isAltered("see (item 1", original: "see (item 1"))
        // While streaming, the end is still held back.
        #expect(r.restore("mail [EMAIL_1", complete: false) == "mail ")
    }

    @Test func ordinaryTextIsNotAKey() {
        for text in ["convertUTF8ToUTF16AndBack42", "getHTTP2ResponseForURLv3Id", "C++/CLI/WinRT/Win32/x64/Release",
                     "wo3xiang3ming2tian1qu4kai1hui4", "ni3hao3ma5wo3hen3hao3xie4xie5ni3", "zhong1guo2ren2min2yin2hang2"] {
            #expect(found("see \(text) here") == [], "\(text)")
        }
    }

    @Test func keysStillCaught() {
        let keys = ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY", "je7MtGbClwBF/2Zp9Utk/h3yCo8nvb+EXAMPLEKEY",
                    "\u{6B}J3x9Qm/Zp2Lw8Rt+Vb5Nc7Yh4Gd1Fs6Ae0Pu3Io", "sk-\u{70}roj-4f9Qx2LmN8pR7tV1wZ3yB6", "sk-\u{61}nt-api03-AbC9xYz_12345678abcdEFGH",
                    "gh\u{70}_1234567890abcdefghijABCDEFGHIJ123456", "xo\u{78}b-1234567890-abcdefghij", "AK\u{49}AIOSFODNN7EXAMPLE",
                    "Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MGFiY2Rl", "dGhpcyBpcyBhIHNlY3JldCB0b2tlbg+/aGVsbG8=",
                    "3f2a9c8b7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a", "9e107d9d372bb6826bd81d3542a419d6", "QWxhZGRpbjpvcGVuIHNlc2FtZQ9xYz7KpL2mN4"]
        for key in keys { #expect(found("key \(key) ok") == ["KEY \(key)"], "\(key)") }
    }

    @Test func gitRemotesAndURLUsersAreNotEmails() {
        #expect(found("git clone git@github.com:org/repo.git") == [])
        #expect(found("open https://user@example.com/path") == [])
        #expect(found("mail bob@acme.com: thanks") == ["EMAIL bob@acme.com"])
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
        #expect(final.result.versions.map(\.text).map { Redaction.isAltered($0) } == [false, false, true])
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

    @Test func converterQuestionKeepsTheUsersOwnIdentifiers() async throws {
        let host = "redact-question.test"
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [
            Self.claudeAnswer("ip_1 holds [IP_3] and ip_2 holds [IP_4]; IP_1 is just a name.")]))
        let converter = converter(host: host, redaction: on)
        var final: ConversionUpdate?
        let input = "Why does ip_1 = '10.0.0.1' and ip_2 = '10.0.0.2' fail?"
        for try await update in converter.generate(.question, input: input) where update.isFinal { final = update }
        let body = Self.body(StubURLProtocol.lastRequest(host: host))
        #expect(!body.contains("10.0.0.") && body.contains("ip_1 = '[IP_3]'"))
        #expect(final?.result.versions.first?.text == "ip_1 holds 10.0.0.1 and ip_2 holds 10.0.0.2; IP_1 is just a name.")
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
