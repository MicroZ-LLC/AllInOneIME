#!/usr/bin/env swift
// Writes and signs update.json, the in-app updater's manifest (Updater in AllInOneIMECore), for the site
// (site/public/, served at https://allinoneime.com/update.json). `make update-manifest` runs it.
//
//   swift Scripts/build-update-manifest.swift --out DIR --zip ZIP --url URL --notes URL
//        --summary-en TEXT --summary-zh TEXT
//        the update archive `make dmg` wrote (build/AllInOneIME-<version>-update.zip) and where it will be
//        downloaded from (its GitHub release asset); the version, build and minimum macOS are read from the
//        apps inside it. Signed with the releases' own key from the login keychain (not the plugins' or the
//        language packs')
//   … --test-key KEYFILE
//        signed with a test key instead (KEYFILE: a raw Ed25519 private key, base64; made if missing, and its
//        public half printed for `AllInOneIME --install-update … --key`), for a local test server
//   swift Scripts/build-update-manifest.swift --create-key
//        once: makes the releases' key and stores it in the login keychain only (never in a file, never
//        printed); prints its public half, for Updater.publicKey and `publicKeyBase64` below
//
// The archive itself is not in the repository: it's a release asset, and `url` points there. The app checks
// the signature before reading update.json, then the archive against its sha256 and size here, then the apps
// inside against the version and build here.

import CryptoKit
import Foundation

let publicKeyBase64 = "+zppTAxWuTfrxrrxaK1aSQUv9fGX/A2gSeIImImme14="
let keychainService = "allinoneime-releases-signing"
let keychainAccount = "weijianz-opc"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

/// Runs `security` with `input` on its standard input; its output, and whether it succeeded.
func security(_ arguments: [String], input: String? = nil) -> (ok: Bool, output: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let output = Pipe(), stdin = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = stdin
    do { try process.run() } catch { return (false, Data()) }
    if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
    try? stdin.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus == 0, data)
}

/// The releases' key from the login keychain (macOS may ask to allow access); never printed.
func keychainKey() -> Curve25519.Signing.PrivateKey? {
    let found = security(["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"])
    guard found.ok, let raw = Data(base64Encoded: String(decoding: found.output, as: UTF8.self)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--create-key"] {
    guard keychainKey() == nil else { fail("the keychain already has a releases key (service \(keychainService)); not replaced") }
    let key = Curve25519.Signing.PrivateKey()
    // Through `security -i`'s standard input, so the secret is never in a process's arguments.
    let command = "add-generic-password -s \(keychainService) -a \(keychainAccount) -l \"AllInOneIME releases signing key\" "
        + "-j \"Ed25519 private key (raw, base64) for update.json; see Scripts/build-update-manifest.swift\" "
        + "-w \(key.rawRepresentation.base64EncodedString())\n"
    _ = security(["-i"], input: command)
    guard keychainKey()?.publicKey.rawRepresentation == key.publicKey.rawRepresentation else {
        fail("couldn't store the key in the login keychain")
    }
    print("✓ stored in the login keychain (service \(keychainService), account \(keychainAccount))")
    print("public key: \(key.publicKey.rawRepresentation.base64EncodedString())")
    exit(0)
}

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let usage = "usage: build-update-manifest.swift [--test-key KEYFILE] --out DIR --zip ZIP --url URL --notes URL --summary-en TEXT --summary-zh TEXT\n"
    + "       build-update-manifest.swift --create-key"
guard let outPath = option("--out"), let zipPath = option("--zip"), let url = option("--url"), let notes = option("--notes"),
      let summaryEn = option("--summary-en"), let summaryZh = option("--summary-zh") else {
    print(usage)
    exit(2)
}
guard !summaryEn.isEmpty, !summaryZh.isEmpty else { fail("the summary is empty in English or Chinese (UPDATE_SUMMARY_EN, UPDATE_SUMMARY_ZH)") }
let testKeyFile = option("--test-key")
// A release is downloaded from GitHub (or allinoneime.com); a test server from this Mac.
let local = url.hasPrefix("http://127.0.0.1") || url.hasPrefix("http://localhost")
guard url.hasPrefix("https://github.com/MicroZ-LLC/AllInOneIME/releases/download/") || url.hasPrefix("https://allinoneime.com/")
        || (testKeyFile != nil && local) else {
    fail("\(url): not a release asset of MicroZ-LLC/AllInOneIME (the app downloads from nowhere else)")
}

// The archive: its size and sha256, and the apps inside, unpacked into a temporary folder to read their versions.
let zip = URL(fileURLWithPath: zipPath)
guard let archive = FileManager.default.contents(atPath: zip.path), !archive.isEmpty else { fail("\(zipPath): no such archive") }
let sha256 = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
let work = FileManager.default.temporaryDirectory.appendingPathComponent("update-manifest-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: work) }
let ditto = Process()
ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
ditto.arguments = ["-x", "-k", zip.path, work.path]
try! ditto.run()
ditto.waitUntilExit()
guard ditto.terminationStatus == 0 else { fail("\(zipPath): can't unpack it") }
func info(_ app: String) -> [String: Any] {
    guard let info = NSDictionary(contentsOf: work.appendingPathComponent("\(app)/Contents/Info.plist")) as? [String: Any] else {
        fail("\(zipPath) has no \(app)")
    }
    return info
}
let ime = info("AllInOneIME.app"), settings = info("AllInOneIME Settings.app")
guard ime["CFBundleIdentifier"] as? String == "com.aipinyin.inputmethod.AIPinyin",
      settings["CFBundleIdentifier"] as? String == "com.aipinyin.settings",
      let version = ime["CFBundleShortVersionString"] as? String, let build = ime["CFBundleVersion"] as? String,
      settings["CFBundleShortVersionString"] as? String == version,
      let minimumSystem = ime["LSMinimumSystemVersion"] as? String else {
    fail("\(zipPath): the apps' bundle IDs or versions don't match")
}
if !local, !url.contains(version) { fail("\(url) doesn't name version \(version)") }

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
    guard let key = keychainKey() else { fail("no releases key in the keychain (service \(keychainService), account \(keychainAccount))") }
    guard key.publicKey.rawRepresentation.base64EncodedString() == publicKeyBase64 else {
        fail("the keychain's releases key doesn't match the app's public key")
    }
    privateKey = key
}

let manifest: [String: Any] = [
    "schema": 1, "generated": ISO8601DateFormatter().string(from: Date()),
    "version": version, "build": build, "minimumSystemVersion": minimumSystem,
    "url": url, "sha256": sha256, "size": archive.count,
    "notesURL": notes, "summary": ["en": summaryEn, "zh": summaryZh],
]
var data = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
data.append(0x0A)
let signature = try! privateKey.signature(for: data)
precondition(privateKey.publicKey.isValidSignature(signature, for: data))
let out = URL(fileURLWithPath: outPath, isDirectory: true)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try! data.write(to: out.appendingPathComponent("update.json"))
try! Data((signature.base64EncodedString() + "\n").utf8).write(to: out.appendingPathComponent("update.json.sig"))
print("✓ \(out.path)/update.json: AllInOneIME \(version) (\(build)), \(archive.count) bytes, sha256 \(sha256), signed into update.json.sig")
