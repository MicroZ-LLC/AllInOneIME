import AllInOneIMECore
import AppKit
import os

/// Sends each request on as it is (to the real service) and keeps its body: what left the Mac.
final class LoggingProxyProtocol: URLProtocol, @unchecked Sendable {
    private static let bodies = OSAllocatedUnfairLock(initialState: [String]())
    static var sent: [String] { bodies.withLock { $0 } }
    static func reset() { bodies.withLock { $0 = [] } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoggingProxyProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var forwardTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var forwarded = request
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        forwarded.httpBodyStream = nil
        forwarded.httpBody = body
        Self.bodies.withLock { $0.append(String(decoding: body, as: UTF8.self)) }
        forwardTask = URLSession.shared.dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            if let error { return self.client?.urlProtocol(self, didFailWithError: error) ?? () }
            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwardTask?.resume()
    }

    override func stopLoading() { forwardTask?.cancel() }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

extension SelfTest {
    /// Hiding sensitive values (live): @improve on a sentence with an email and a phone number. What was sent (the
    /// logging proxy) holds placeholders, never the values; the versions have the values back; the panel says how
    /// many were hidden; the version picked goes in with them.
    static func testRedaction(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        print("— hiding sensitive information from the AI (live)")
        let (converterBefore, document, inserted) = (controller.converter, client.document, client.inserted)
        defer {
            controller.converter = converterBefore
            controller.commitComposition(client)
            (client.document, client.inserted, client.selection, client.insertionPoint) = (document, inserted, nil, nil)
        }
        let email = "bob.tester@example.com", phone = "555-123-4567"
        LoggingProxyProtocol.reset()
        controller.converter = Converter(client: BedrockClient(session: LoggingProxyProtocol.session()), loadConfig: {
            var config = try Config.load()
            config.setOrder([OutputLanguage.english])
            config.rewriteStyles = ["简洁"]
            config.redaction = RedactionSettings(enabled: true)
            return config
        })
        let text = "pls tell \(email) the meeting moved, or call \(phone) tomorow"
        controller.commitComposition(client)
        (client.document, client.selection, client.insertionPoint, client.marked) = (text, NSRange(location: 0, length: (text as NSString).length), nil, "")
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("i", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        _ = enter(controller, client)
        guard finishConversion(controller, "@improve with an email and a phone number") else { return }
        let sent = LoggingProxyProtocol.sent
        check(!sent.isEmpty && sent.allSatisfy { !$0.contains(email) && !$0.contains(phone) && !$0.contains("555") }
              && sent.contains { $0.contains("[EMAIL_1]") && $0.contains("[PHONE_1]") },
              "the request held [EMAIL_1] and [PHONE_1], never the email or the number (\(sent.count) sent)")
        let versions = controller.composer.choices.filter { $0.kind == .version }.map(\.text)
        check(!versions.isEmpty && versions.allSatisfy { $0.contains(email) && $0.contains(phone) && !$0.contains("[") },
              "every version has the real email and number back (\(versions))")
        let model = controller.panelModel()
        check(controller.lastHidden == 2 && model.detail?.hasPrefix(RedactionPanel.hiddenLine(2)) == true
              && !model.rows.contains { $0.comment.contains(RedactionPanel.changed) },
              "the panel says what was hidden, quietly (\(model.detail ?? "-"))")
        snapshot("redaction", in: snapshotDirectory)
        // A placeholder the model changed past telling: the row as written, marked.
        var choices = controller.composer.choices
        if let row = choices.firstIndex(where: { $0.kind == .version }) {
            choices[row].text = "Please let [EMAIL_9] know the meeting has moved."
            var altered = model
            altered.rows[row].comment = ""
            altered.detail = nil
            RedactionPanel.annotate(&altered, choices: choices, hidden: 2, phase: .choosing)
            check(altered.rows[row].comment == RedactionPanel.changed
                  && altered.rows.indices.filter { altered.rows[$0].comment.contains(RedactionPanel.changed) } == [row],
                  "a row whose placeholder was changed is marked \"\(RedactionPanel.changed)\", the others aren't")
            altered.rows[row].text = choices[row].text
            CandidatePanel.shared.show(altered, anchor: client.caretRect)
            snapshot("redaction-changed", in: snapshotDirectory)
            CandidatePanel.shared.show(model, anchor: client.caretRect)
        }
        _ = enter(controller, client)
        check(client.document.contains(email) && client.document.contains(phone) && !client.document.contains("[EMAIL"),
              "the version picked goes in with the real values ('\(client.document)')")

        // Without hiding (the setting off), the panel says nothing of it.
        var shown = CandidateView.Model()
        RedactionPanel.annotate(&shown, choices: [], hidden: 0, phase: .choosing)
        check(shown.detail == nil, "nothing hidden: no line about it")
    }
}
