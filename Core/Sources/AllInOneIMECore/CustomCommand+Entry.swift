import Foundation

extension CustomCommand {
    /// An entry of `Config.customCommands` as the file has it: a command this version reads; the JSON of one whose
    /// `type` is a string this version doesn't know and whose `name` is a string (a later version's: kept,
    /// `Config.unreadCustomCommands`); or the JSON of any other it can't read, refused with its reason
    /// (`Config.refusedCustomCommands`, decision 25). No entry is an error for the whole list.
    struct Entry: Decodable {
        var command: CustomCommand?
        var unread: AIConfig.JSONValue?
        var refused: Refused?

        init(from decoder: Decoder) throws {
            do {
                command = try CustomCommand(from: decoder)
            } catch {
                guard let json = try? AIConfig.JSONValue(from: decoder) else { throw error }
                if Self.name(json) != nil { unread = json } else { refused = Refused(json) }
            }
        }

        /// The name of an entry of a later version's (a JSON object whose `type` this version doesn't know and whose
        /// `name` is a string), or nil when it isn't one.
        static func name(_ json: AIConfig.JSONValue) -> String? {
            guard case let .object(fields) = json, case let .string(type)? = fields["type"], CommandType(rawValue: type) == nil,
                  case let .string(name)? = fields["name"] else { return nil }
            return name
        }
    }
}
