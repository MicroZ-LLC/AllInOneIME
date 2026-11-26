import AllInOneIMECore
import Foundation

extension RimeService {
    /// `englishDictionary`, waited for `timeout` seconds at most while it is being read: never on the main thread (tests,
    /// what checks the dictionary once librime has started).
    public func englishDictionary(waitingUpTo timeout: TimeInterval) -> EnglishDictionary? {
        guard let englishLoad else { return nil }
        _ = englishLoad.reading.wait(timeout: .now() + timeout)
        return englishLoad.dictionary
    }
}
