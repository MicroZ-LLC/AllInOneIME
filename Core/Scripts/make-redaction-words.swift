#!/usr/bin/env swift
// Writes Sources/AllInOneIMECore/Resources/RedactionWords.txt, the English words the key detector knows
// (`RedactionWords.english`), so that the core has them on every system: before, it read /usr/share/dict/words, which
// only Macs and some Linux systems have. A resource of the core (Package.swift), not code: compiled in (string
// literals, until 0.7.6), the list made the binary 2.5 MB larger and was parsed into a `Set` when first used (about
// 35 ms, and 11 MB kept); the file is searched as it lies.
//
//   swift Scripts/make-redaction-words.swift    (make redaction-words) from /usr/share/dict/web2
//
// web2 is Webster's Second International (1934), public domain (THIRD_PARTY_NOTICES.md); on macOS
// /usr/share/dict/words is a link to it. Only the copy whose SHA-256 is pinned here is taken, so that the list never
// changes unnoticed. Its words as the core read them: each line of 3 characters or more, lowercased; deduplicated and
// sorted by their bytes, a word a line (LF, the last one too), nothing else: `SortedWordList` searches the file as it
// is, by halves.

import CryptoKit
import Foundation

let source = "/usr/share/dict/web2"
let pinnedSHA256 = "be41ad97963bf8dabedd5871d5d691596175269d540956b0f9965a885c2bbab9"
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/AllInOneIMECore/Resources/RedactionWords.txt")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-redaction-words: \(message)\n".utf8))
    exit(1)
}

guard let data = FileManager.default.contents(atPath: source) else { fail("can't read \(source)") }
let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
guard digest == pinnedSHA256 else { fail("\(source) isn't the pinned copy (SHA-256 \(digest), not \(pinnedSHA256))") }

// As RedactionWords read the system's list: lines of 3 characters or more, lowercased. Only ASCII letters and "-", so
// that the bytes' order is the words' and no line ending or other separator can be in one.
let text = String(decoding: data, as: UTF8.self)
let words = Set(text.split(separator: "\n").filter { $0.count >= 3 }.map { $0.lowercased() })
    .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
for word in words where !word.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) {
    fail("unexpected word: \(word.debugDescription)")
}

do {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(words.map { $0 + "\n" }.joined().utf8).write(to: output, options: .atomic)
} catch {
    fail("can't write \(output.path): \(error)")
}
print("make-redaction-words: \(words.count) words from \(source) in \(output.path)")
