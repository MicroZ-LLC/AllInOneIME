import Foundation
@testable import AllInOneIMECore

/// 0.6.4 added a rule about live data (the weather, news, prices …) at the end of @question's system prompt
/// (`Prompt.liveDataRule`). The acceptance tests' goldens are what release 0.6.3 sent, without it: `strip` takes it out
/// of a request before it is compared with them, so everything else is still checked byte for byte.
enum LiveDataRule {
    static let added = " " + Prompt.liveDataRule

    static func strip(_ text: String) -> String { text.replacingOccurrences(of: added, with: "") }
    static func strip(_ data: Data) -> Data { Data(strip(String(decoding: data, as: UTF8.self)).utf8) }
}
