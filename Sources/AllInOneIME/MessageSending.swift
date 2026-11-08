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

    /// The contacts, read again at most every `maxAge` seconds. Asks for access when it was never asked.
    static func load() async -> Lookup {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: loadNow())
            }
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

    private static func loadNow(fresh: Bool = false) -> Lookup {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            let asked = DispatchSemaphore(value: 0)
            var granted = false
            CNContactStore().requestAccess(for: .contacts) { ok, _ in
                granted = ok
                asked.signal()
            }
            asked.wait()
            log.notice("@imessage: Contacts access \(granted ? "allowed" : "denied", privacy: .public)")
            guard granted else { return .denied }
        case .denied, .restricted:
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

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        let input = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(MessageScript.iMessage.utf8))
        try? input.fileHandleForWriting.close()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        // Only the error number is kept (the message can name the recipient).
        throw MessageSendError.from(osascriptError: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
