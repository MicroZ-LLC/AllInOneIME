#!/usr/bin/env swift
// Writes and signs packs.json, the language pack library's index (LanguagePackLibrary), for the language
// library repository MicroZ-LLC/AllInOneIME-languages (served at https://languages.allinoneime.com/packs.json).
//
//   swift Scripts/build-packs-index.swift OUT_DIR ENTRY.json...
//        the entries `make pack` wrote (build/packs/*.tar.xz.json), every version on offer; signed with the
//        language packs' own key from the login keychain (not the plugins')
//   swift Scripts/build-packs-index.swift --test-key KEYFILE OUT_DIR ENTRY.json...
//        signed with a test key instead (KEYFILE: a raw Ed25519 private key, base64; made if missing, and
//        its public half printed for `AllInOneIME --install-pack … --key`), for a local test server
//
// The archives themselves are not in the repository (too large for git): they are release assets, and
// each entry's url points there. The app checks the signature before reading packs.json, then each
// archive against its sha256 and size here.

import CryptoKit
import Foundation

let publicKeyBase64 = "MYnQfpeOxhKUAowyQUmJU0RgCZe5/tA8oFc2YszlGQ8="
let keychainService = "allinoneime-languages-signing"
let keychainAccount = "weijianz-opc"

var arguments = Array(CommandLine.arguments.dropFirst())
var testKeyFile: String?
if arguments.first == "--test-key", arguments.count > 1 {
    testKeyFile = arguments[1]
    arguments.removeFirst(2)
}
guard arguments.count >= 2 else {
    print("usage: build-packs-index.swift [--test-key KEYFILE] OUT_DIR ENTRY.json...")
    exit(2)
}
let out = URL(fileURLWithPath: arguments[0], isDirectory: true)

var packs: [[String: Any]] = []
for path in arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path),
          let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          entry["id"] is String, entry["version"] is String,
          let sha = entry["sha256"] as? String, sha.count == 64, (entry["size"] as? Int ?? 0) > 0,
          let url = entry["url"] as? String, url.hasPrefix("https://") || !url.contains(":") else {
        print("✗ \(path): not a pack entry (id, version, sha256, size, url)")
        exit(1)
    }
    packs.append(entry)
}
packs.sort { ($0["id"] as! String, $1["version"] as! String) < ($1["id"] as! String, $0["version"] as! String) }

let privateKey: Curve25519.Signing.PrivateKey
if let testKeyFile {
    if let text = try? String(contentsOfFile: testKeyFile, encoding: .utf8),
       let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
       let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
        privateKey = key
    } else {
        privateKey = Curve25519.Signing.PrivateKey()
        try! Data((privateKey.rawRepresentation.base64EncodedString() + "\n").utf8).write(to: URL(fileURLWithPath: testKeyFile))
    }
    print("test public key: \(privateKey.publicKey.rawRepresentation.base64EncodedString())")
} else {
    // The private key comes from the login keychain (macOS may ask to allow access); never printed.
    let security = Process()
    security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    security.arguments = ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
    let pipe = Pipe()
    security.standardOutput = pipe
    try! security.run()
    let secret = pipe.fileHandleForReading.readDataToEndOfFile()
    security.waitUntilExit()
    guard security.terminationStatus == 0,
          let raw = Data(base64Encoded: String(decoding: secret, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        print("✗ no signing key in the keychain (service \(keychainService), account \(keychainAccount))")
        exit(1)
    }
    guard key.publicKey.rawRepresentation.base64EncodedString() == publicKeyBase64 else {
        print("✗ the keychain's signing key doesn't match the app's public key")
        exit(1)
    }
    privateKey = key
}

let index: [String: Any] = ["schema": 1, "generated": ISO8601DateFormatter().string(from: Date()), "packs": packs]
var data = try! JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
data.append(0x0A)
let signature = try! privateKey.signature(for: data)
precondition(privateKey.publicKey.isValidSignature(signature, for: data))
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! data.write(to: out.appendingPathComponent("packs.json"))
try! Data((signature.base64EncodedString() + "\n").utf8).write(to: out.appendingPathComponent("packs.json.sig"))
print("✓ \(out.path)/packs.json: \(packs.count) pack version(s), signed into packs.json.sig")
