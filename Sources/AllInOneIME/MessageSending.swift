import AllInOneIMECore
import AllInOneIMEMac
import Contacts
import Foundation

/// The address book for `@imessage`: names, phone numbers and email addresses only. Access is asked
/// for the first time `@imessage` is typed (never at launch); everything runs off the main thread.
enum ContactBook {
    enum Lookup {
        case contacts([Contact])
        /// The user said no (or it is restricted): numbers and addresses can still be typed.
        case denied
    }

    private static let lock = NSLock()
    private static var book: (at: Date, contacts: [Contact])?
    /// A read of the book is under way in the background (`cached`).
    private static var reading = false
    /// How long the book read is used before it is read again (in the background: the keys meanwhile use it as it is).
    static let maxAge: TimeInterval = 60
    /// How long macOS's prompt for access to Contacts is waited for: unanswered by then, `@imessage` goes on without the
    /// address book (`denied`) and asks again the next time. ALLINONEIME_CONTACTS_AUTH_TIMEOUT, a number of seconds
    /// above 0, says otherwise (the tests').
    static let authorizationTimeout: TimeInterval = ProcessInfo.processInfo.environment["ALLINONEIME_CONTACTS_AUTH_TIMEOUT"]
        .flatMap(TimeInterval.init).flatMap { $0 > 0 ? $0 : nil } ?? 60

    /// The contacts, read again at most every `maxAge` seconds. Asks for access when it was never asked.
    static func load() async -> Lookup {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            let granted = await requestAccess(within: authorizationTimeout)
            log.notice("@imessage: Contacts access \(granted ? "allowed" : "denied or not answered", privacy: .public)")
            guard granted else { return .denied }
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: loadNow())
            }
        }
    }

    /// Asks for access to Contacts (macOS's prompt, the first time): whether it was allowed; false when the user said no
    /// or hasn't answered within `seconds`. Nothing waits on a thread meanwhile.
    private static func requestAccess(within seconds: TimeInterval) async -> Bool {
        let waiting = Locked<CheckedContinuation<Bool, Never>?>(initialState: nil)
        @Sendable func answer(_ granted: Bool) {
            let continuation = waiting.withLock { waiting -> CheckedContinuation<Bool, Never>? in
                defer { waiting = nil }
                return waiting
            }
            continuation?.resume(returning: granted)
        }
        return await withCheckedContinuation { continuation in
            waiting.withLock { $0 = continuation }
            CNContactStore().requestAccess(for: .contacts) { granted, _ in answer(granted) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { answer(false) }
        }
    }

    /// The contacts as last read, at once, for a key (nil: not read yet, or no access): one read more than `maxAge`
    /// ago is read again in the background, and used as it is meanwhile. Never asks for access, never waits for the lock
    /// a read holds.
    static func cached() -> [Contact]? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        guard let book else { return nil }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if Date().timeIntervalSince(book.at) >= maxAge, !reading, status != .notDetermined, status != .denied, status != .restricted {
            reading = true
            DispatchQueue.global(qos: .utility).async {
                _ = loadNow(fresh: true)
                lock.withLock { reading = false }
            }
        }
        return book.contacts
    }

    /// The book read (unless one less than `maxAge` old is kept and not `fresh`), once access was allowed (`load` asks
    /// for it first).
    private static func loadNow(fresh: Bool = false) -> Lookup {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined, .denied, .restricted:
            return .denied
        default:
            break  // authorized (or limited)
        }
        if !fresh, let book = lock.withLock({ book }), Date().timeIntervalSince(book.at) < maxAge { return .contacts(book.contacts) }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var contacts: [Contact] = []
        do {
            try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { card, _ in
                let handles = card.phoneNumbers.map(\.value.stringValue) + card.emailAddresses.map { $0.value as String }
                guard !handles.isEmpty else { return }
                let name = Contact.displayName(given: card.givenName, family: card.familyName, nickname: card.nickname,
                                               organization: card.organizationName)
                contacts.append(Contact(name: name, otherNames: [card.nickname, card.organizationName], handles: handles))
            }
        } catch {
            log.error("@imessage: reading Contacts failed: \((error as NSError).code, privacy: .public)")
            return .denied
        }
        log.notice("@imessage: \(contacts.count, privacy: .public) contacts with a phone number or email")
        lock.withLock { book = (Date(), contacts) }
        return .contacts(contacts)
    }
}

/// The handles last messaged with `@imessage` (handles only, no names or text), most recent first.
enum RecentRecipients {
    private static let key = "recentMessageHandles"

    static var handles: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Sends iMessages by asking Messages (Apple events) to run `MessageScript.iMessage`, with the handle
/// and the text as the script's arguments. Runs osascript off the main thread.
struct AppleScriptMessageSender: MessageSender {
    static let messagesApp = "/System/Applications/Messages.app"

    func send(_ text: String, to recipient: Recipient) async throws {
        guard FileManager.default.fileExists(atPath: Self.messagesApp) else { throw MessageSendError.appMissing }
        let arguments = MessageScript.osascriptArguments(handle: recipient.handle, text: text)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.run(arguments) })
            }
        }
    }

    /// osascript with the script on its standard input (`Osascript`). Messages not answering within its timeout fails
    /// as an Apple event that timed out does (errAETimeout).
    private static func run(_ arguments: [String]) throws {
        let result: ProcessOutput.Result
        do {
            result = try Osascript.run(arguments, input: Data(MessageScript.iMessage.utf8))
        } catch is ProcessOutput.TimedOut {
            log.error("@imessage: Messages didn't answer within \(Osascript.timeout, privacy: .public) s")
            throw MessageSendError.failed(code: -1712)  // errAETimeout
        }
        guard result.status != 0 else { return }
        // Only the error number is kept (the message can name the recipient).
        let message = String(decoding: result.errors, as: UTF8.self)
        throw MessageSendError.from(osascriptError: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
