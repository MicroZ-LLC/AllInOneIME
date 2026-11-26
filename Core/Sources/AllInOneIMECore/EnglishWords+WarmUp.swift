import Foundation

extension EnglishWordsEngine.Words {
    /// What the first English word learned would read from disk on the thread keys are answered on, read now on the
    /// caller's (the shell's, off the main thread, as it makes the words ahead: `prepare`): the word list the key
    /// detector tells an ordinary word by (`RedactionWords.english`, a file of the core's resources mapped when first
    /// needed).
    public static func prepareLearning() {
        RedactionWords.load()
    }
}
