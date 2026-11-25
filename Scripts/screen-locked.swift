// Prints "locked" when this login session's screen is locked (or no one is logged in at the console), else "unlocked".
// Quality's test job uses it: tests that need windows drawn on screen can't pass while the Mac mini's screen is locked.
import CoreGraphics

let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
let onConsole = (session["kCGSSessionOnConsoleKey"] as? Bool) ?? false
print(locked || !onConsole ? "locked" : "unlocked")
