import Foundation
import Testing
@testable import AllInOneIMECore

/// What the command list costs a keystroke with many script extensions: the composer's work for the key, and
/// what the controller reads to draw the panel (`panelModel`, `refreshStatuses`, the marked text), measured
/// over typed names and ⌫, in the CPU time of the thread typing (`Timing`: the suite's load doesn't add to it). Printed
/// for the record; the bound is loose (machines differ).
struct ExtensionPerformanceTests {
    /// `count` extension commands with made-up names, titles and keywords.
    static func commands(_ count: Int) -> [Command] {
        var generator = SystemRandomNumberGenerator()
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let scripts = (0..<count).map { index -> ScriptCommand in
            let name = String((0..<8).map { _ in letters.randomElement(using: &generator)! }) + String(index)
            return ScriptCommand(file: URL(fileURLWithPath: "/x/\(name).sh"), name: name,
                                 title: "Command \(name) does \(index % 7 == 0 ? "lists" : "things") for you",
                                 keywords: ["alpha", "beta\(index % 10)"])
        }
        return Command.catalog([], scripts: scripts)
    }

    /// The controller's reads for one key while the list is shown (see `AllInOneIMEInputController.panelModel`).
    static func panelReads(_ c: Composer) {
        _ = c.markedText
        _ = c.markedCursor
        guard c.paletteQuery != nil else { return }
        let first = c.paletteFirstVisible, total = c.paletteMatches.count
        _ = c.paletteVisible.map(\.name)
        _ = c.paletteHighlighted - first + total
        let matches = c.paletteMatches
        _ = matches.indices.contains(c.paletteHighlighted)
        _ = c.paletteQuery != nil ? c.paletteVisible.compactMap(\.script) : []  // refreshStatuses
    }

    /// Milliseconds a key takes on average: typing "@", letters, then ⌫ them, again and again.
    static func perKey(_ count: Int) -> Double {
        let commands = commands(count)
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = commands
        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
        // Another word each round: each letter typed is a query not asked before (⌫ goes back over known ones).
        let words = ["beta", "cmdx", "does", "list", "zqvw", "alph", "thin", "comm", "abcd", "mnop",
                     "fors", "yous", "beta1", "rstu", "efgh", "ijkl", "wxyz", "lmno", "ghij", "opqr"]
        var spent: Duration = .zero
        var pressed = 0
        for word in words {
            let keys = [at] + word.map { k(String($0)) } + Array(repeating: backspaceKey, count: word.count + 1)
            for key in keys {
                spent += Timing.cpuTime {
                    _ = c.handleKeyDown(key)
                    panelReads(c)
                }
                pressed += 1
            }
        }
        return Double(spent.components.attoseconds) / 1e15 / Double(pressed) + Double(spent.components.seconds) * 1000 / Double(pressed)
    }

    /// Milliseconds a key takes inside another command's text: "@question hello " then "@", letters and ⌫.
    static func perKeyInside(_ count: Int) -> Double {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        c.commands = commands(count)
        let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
        for key in [at] + "question".map({ k(String($0)) }) + [spaceKey] + "hello ".map({ $0 == " " ? spaceKey : k(String($0)) }) {
            _ = c.handleKeyDown(key)
        }
        var spent: Duration = .zero
        var pressed = 0
        for word in ["calc", "py", "js", "zz", "ca", "pyj", "jsx", "cal"] {
            for key in [at] + word.map({ k(String($0)) }) + Array(repeating: backspaceKey, count: word.count + 1) {
                spent += Timing.cpuTime {
                    _ = c.handleKeyDown(key)
                    panelReads(c)
                }
                pressed += 1
            }
        }
        return (Double(spent.components.seconds) * 1000 + Double(spent.components.attoseconds) / 1e15) / Double(pressed)
    }

    /// Milliseconds the controller spends on the command list for a key typed outside a command: building the
    /// catalog and comparing it with the one before (as it did), and asking the `CatalogCache` (as it does).
    static func catalogPerKey(_ count: Int) -> (rebuilt: Double, cached: Double) {
        let scripts = commands(count).compactMap(\.script)
        var index = ExtensionIndex(commands: scripts)
        index.generation = 1
        var previous = Command.catalog([], scripts: scripts)
        let rebuilt = Timing.cpuTime {
            for _ in 0..<50 {
                let catalog = Command.catalog([], scripts: index.enabled([]))
                if catalog != previous { previous = catalog }
            }
        }
        var cache = CatalogCache()
        _ = cache.catalog([], plugins: [], index: index, disabled: [])
        let cached = Timing.cpuTime {
            for _ in 0..<50 { _ = cache.catalog([], plugins: [], index: index, disabled: []) }
        }
        func ms(_ d: Duration) -> Double { (Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15) / 50 }
        return (ms(rebuilt), ms(cached))
    }

    @Test func typingStaysFast() {
        let small = Self.perKey(300), large = Self.perKey(1000)
        print(String(format: "command list per key: 300 extensions %.3f ms, 1000 extensions %.3f ms", small, large))
        #expect(large < 5, "per key at 1000 extensions: \(large) ms")  // a debug build on a slow machine has room
        let (insideSmall, insideLarge) = (Self.perKeyInside(300), Self.perKeyInside(1000))
        print(String(format: "command list inside a text per key: 300 extensions %.3f ms, 1000 extensions %.3f ms", insideSmall, insideLarge))
        #expect(insideLarge < 5)
        for count in [300, 1000] {
            let (rebuilt, cached) = Self.catalogPerKey(count)
            print(String(format: "catalog per key outside a command, %d extensions: rebuilt and compared %.3f ms, cached %.4f ms",
                         count, rebuilt, cached))
            #expect(cached < 0.5)
        }
    }
}
