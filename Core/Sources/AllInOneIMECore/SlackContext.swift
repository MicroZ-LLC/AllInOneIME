import Foundation

/// Slack's desktop app (`AppContextAdapter`): the channel in front and its last messages, read with Accessibility once
/// the shell has turned Slack's web content tree on (`AXManualAccessibility`, as the input method does for Slack in
/// front). What Slack shows there (checked on the owner's Mac, Slack 4.x):
/// - the page is an AXWebArea whose AXURL is the client's, https://app.slack.com/client/<TEAM>/<CHANNEL>;
/// - the messages are an AXList titled with the channel's name; each message an AXGroup whose AXTitle holds the sender,
///   the text and the time; its timestamp an AXLink whose AXURL is the message's permalink,
///   https://<workspace>.slack.com/archives/<CHANNEL>/p<ts>;
/// - the composer is the focused AXTextArea, its AXValue the draft.
/// The list is looked for near the focused field first (up from it, the nearest list with permalinks: the channel's, or
/// a thread's when the thread's composer has the focus), within a few hundred elements; then the last
/// `AppSnapshot.Limits.messages` messages on screen are read, each within `nodesPerMessage` elements.
public struct SlackAdapter: AppContextAdapter {
    public static let bundleID = "com.tinyspeck.slackmacgap"
    /// The most elements looked at to find the list, and in each message.
    static let searchNodes = 600
    static let nodesPerMessage = 60

    /// The time zone a message's time is given in (the Mac's).
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) { self.timeZone = timeZone }

    public var bundleIDs: Set<String> { [Self.bundleID] }

    public func read(_ app: any AppAccess, marked: String, deadline: AppDeadline) -> AppDetail? {
        let focused = app.focusedElement()
        let focusedNode = focused?.read()
        var detail = AppDetail(kind: "slack")
        if let node = focusedNode, ["AXTextArea", "AXTextField"].contains(node.role), !node.isPassword {
            detail.draft = AppSnapshot.draft(node.value, without: marked)
        }
        // The way up from the focus to the page (its web area), else the page in the window.
        var ancestors: [any AppElement] = focused.map { [$0] } ?? []
        var web: (element: any AppElement, node: AppNode)?
        var current = focused?.parent()
        while let element = current, ancestors.count < 80, !deadline.isPast {
            let node = element.read()
            if node.role == "AXWebArea" {
                web = (element, node)
                break
            }
            ancestors.append(element)
            current = element.parent()
        }
        var budget = Self.searchNodes
        if web == nil {
            ancestors = []
            if let window = app.focusedWindow() {
                web = Self.first(in: window, budget: &budget, deadline: deadline) { $0.role == "AXWebArea" }
            }
        }
        guard let web else { return detail.draft == nil ? nil : detail }
        let client = Self.client(web.node.url)
        // The messages: the nearest list up from the focus that has permalinks, else the first in the page.
        var list: (element: any AppElement, node: AppNode)?
        var below: (any AppElement)?
        for ancestor in ancestors + [web.element] {
            list = Self.messageList(in: ancestor, skipping: below, budget: &budget, deadline: deadline)
            if list != nil || deadline.isPast || budget <= 0 { break }
            below = ancestor
        }
        var messages: [AppMessage] = []
        if let list {
            // Real Slack reports its message list's frame as 1×1 (seen 2026-11-12): then what shows is the page's frame.
            let listFrame = list.node.frame.flatMap { $0.height > 40 ? $0 : nil }
            let viewFrame = listFrame ?? web.node.frame
            for item in list.element.children().reversed() {
                guard messages.count < AppSnapshot.Limits.messages, !deadline.isPast else { break }
                let node = item.read()
                if let view = viewFrame, let frame = node.frame {
                    if frame.minY >= view.maxY || frame.height <= 1 { continue }  // below what shows (or off screen)
                    if frame.maxY <= view.minY { break }  // above it: so is every one before it
                }
                if let message = message(in: item, node: node, deadline: deadline) { messages.append(message) }
            }
        }
        messages.reverse()
        // A run of one person's messages shows their name once: each without a sender of its own is the one before's.
        var sender: String?
        for index in messages.indices {
            if let own = messages[index].sender { sender = own } else { messages[index].sender = sender }
        }
        detail.messages = messages
        let link = messages.compactMap { $0.link.flatMap(Self.permalink) }.last
        let channelName = list?.node.title.map(Self.cleanChannel)
        detail.fields = [("channel", channelName), ("channel_id", client?.channel ?? link?.channel), ("team_id", client?.team),
                         ("workspace", link?.workspace), ("url", web.node.url)]
            .compactMap { name, value in value.flatMap { $0.isEmpty ? nil : AppDetail.Field(name, $0) } }
        return detail
    }

    // MARK: Walking

    /// The first element below `root` (depth first, `root` included) that `matches`, within `budget` elements.
    static func first(in root: any AppElement, budget: inout Int, deadline: AppDeadline,
                      _ matches: (AppNode) -> Bool) -> (element: any AppElement, node: AppNode)? {
        var stack: [any AppElement] = [root]
        while let element = stack.popLast(), budget > 0, !deadline.isPast {
            budget -= 1
            let node = element.read()
            if matches(node) { return (element, node) }
            stack += element.children().reversed()
        }
        return nil
    }

    /// The roles a list is never inside (what shows text, not structure): not walked into.
    static let leaves: Set = ["AXStaticText", "AXTextArea", "AXTextField", "AXImage", "AXButton", "AXLink", "AXCheckBox",
                              "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXHeading"]

    /// The first list in `root` (`skipping` the subtree of the element below it, looked at already) whose messages have
    /// permalinks.
    static func messageList(in root: any AppElement, skipping: (any AppElement)?, budget: inout Int,
                            deadline: AppDeadline) -> (element: any AppElement, node: AppNode)? {
        var stack: [any AppElement] = [root]
        while let element = stack.popLast(), budget > 0, !deadline.isPast {
            if let skipping, element.isSame(skipping) { continue }
            budget -= 1
            let node = element.read()
            if node.role == "AXList" {
                if holdsPermalinks(element, budget: &budget, deadline: deadline) { return (element, node) }
                continue  // a list of something else (the sidebar's channels): not inside it either
            }
            guard !leaves.contains(node.role) else { continue }
            stack += element.children().reversed()
        }
        return nil
    }

    /// Whether one of the last few items of `list` has a permalink.
    static func holdsPermalinks(_ list: any AppElement, budget: inout Int, deadline: AppDeadline) -> Bool {
        for item in list.children().suffix(3).reversed() {
            var own = nodesPerMessage
            if first(in: item, budget: &own, deadline: deadline, { $0.role == "AXLink" && permalink($0.url) != nil }) != nil {
                budget -= nodesPerMessage - own
                return true
            }
            budget -= nodesPerMessage - own
        }
        return false
    }

    /// One item of the message list as a message: the permalink's link (the timestamp), the message's group (the nearest
    /// one above it with a title), its sender (a button before the link whose name the title starts with). Nil: no
    /// permalink (a day's divider, "new messages").
    func message(in item: any AppElement, node itemNode: AppNode, deadline: AppDeadline) -> AppMessage? {
        // Depth first, with the way down to each element.
        var stack: [(element: any AppElement, path: [AppNode])] = [(item, [])]
        var budget = Self.nodesPerMessage
        var buttons: [String] = []
        while let (element, path) = stack.popLast(), budget > 0, !deadline.isPast {
            budget -= 1
            let node = element === item ? itemNode : element.read()
            if node.role == "AXLink", let url = node.url, let link = Self.permalink(url) {
                let group = (path + [node]).last { ($0.role == "AXGroup" || $0.role == "AXListItem") && $0.text?.isEmpty == false }
                let title = group?.text ?? ""
                let shown = node.text
                let sender = buttons.first { !$0.isEmpty && title.hasPrefix($0) }
                let text = Self.text(of: title, sender: sender, time: shown)
                guard !text.isEmpty else { return nil }
                let time = link.date.map(timeText) ?? shown
                return AppMessage(sender: sender, text: text, time: time, link: url)
            }
            if node.role == "AXButton", let name = node.text { buttons.append(name) }
            guard node.role != "AXStaticText", node.role != "AXImage" else { continue }
            stack += element.children().reversed().map { ($0, path + [node]) }
        }
        return nil
    }

    // MARK: Parsing

    /// The team's and channel's ids in the client's address (https://app.slack.com/client/<TEAM>/<CHANNEL>…).
    public static func client(_ url: String?) -> (team: String, channel: String)? {
        guard let url, let components = URLComponents(string: url) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let at = parts.firstIndex(of: "client"), parts.count > at + 2 else { return nil }
        let (team, channel) = (parts[at + 1], parts[at + 2])
        guard isID(team), isID(channel) else { return nil }
        return (team, channel)
    }

    /// A message's permalink (https://<workspace>.slack.com/archives/<CHANNEL>/p<ts>): the workspace's host, the
    /// channel's id, the message's time.
    public static func permalink(_ url: String?) -> (workspace: String, channel: String, date: Date?)? {
        guard let url, let components = URLComponents(string: url), let host = components.host, host.hasSuffix("slack.com") else {
            return nil
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let at = parts.firstIndex(of: "archives"), parts.count > at + 2, isID(parts[at + 1]) else { return nil }
        let stamp = parts[at + 2]
        guard stamp.hasPrefix("p"), stamp.count > 7, stamp.dropFirst().allSatisfy(\.isASCII), stamp.dropFirst().allSatisfy(\.isNumber) else {
            return nil
        }
        // p1762944120000100: seconds, then six digits of microseconds.
        let digits = stamp.dropFirst()
        let date = Double(digits.dropLast(6)).map { Date(timeIntervalSince1970: $0) }
        return (host, parts[at + 1], date)
    }

    static func isID(_ text: String) -> Bool {
        text.count >= 5 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    /// A message's group title without its sender (at the start) and the time it shows (the timestamp link's text),
    /// and the separators left around them.
    static func text(of title: String, sender: String?, time: String?) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sender, !sender.isEmpty, text.hasPrefix(sender) { text.removeFirst(sender.count) }
        if let time = time?.trimmingCharacters(in: .whitespaces), !time.isEmpty {
            if text.hasSuffix(time) {
                text.removeLast(time.count)
            } else if text.trimmingCharacters(in: .whitespaces).hasPrefix(time), let range = text.range(of: time) {
                text.removeSubrange(range)
            }
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,;|-–—·"))
        while let first = text.unicodeScalars.first, separators.contains(first) { text.removeFirst() }
        while let last = text.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|·")).contains(last) {
            text.removeLast()
        }
        return text
    }

    /// The channel's name as the list's title has it, without a leading "#".
    static func cleanChannel(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("#") { name.removeFirst() }
        return name
    }

    /// "2026-11-12 10:42 +08:00" in `timeZone`, with its offset (whoever reads the block may be elsewhere).
    func timeText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let offset = timeZone.secondsFromGMT(for: date) / 60
        return String(format: "%04d-%02d-%02d %02d:%02d %@%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0,
                      offset < 0 ? "-" : "+", abs(offset) / 60, abs(offset) % 60)
    }
}
