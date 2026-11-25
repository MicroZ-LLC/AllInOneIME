import Foundation

/// How the candidate panel's settings, its layout (`Config.candidateLayout`) and its key hints (`Config.keyHints`), are
/// read from a config file and written to it: out of `init(from:)` and `encode(to:)`, already long.
extension Config {
    /// The layout and the key hints in `c`. Not chosen (a file from before the setting) or a layout a later version
    /// added: `d`'s, in a row; key hints not there (a file from before the switch): `d`'s, on.
    static func decodePanel(_ c: KeyedDecodingContainer<CodingKeys>, default d: Config) throws -> (CandidateArrangement, Bool) {
        let layout = (try? c.decodeIfPresent(CandidateArrangement.self, forKey: .candidateLayout)).flatMap { $0 } ?? d.candidateLayout
        return (layout, try c.decodeIfPresent(Bool.self, forKey: .keyHints) ?? d.keyHints)
    }

    /// The layout and, only once turned off, the key hints: a file from before the switch doesn't gain the key.
    func encodePanel(into c: inout KeyedEncodingContainer<CodingKeys>) throws {
        try c.encode(candidateLayout, forKey: .candidateLayout)
        if !keyHints { try c.encode(keyHints, forKey: .keyHints) }
    }
}
