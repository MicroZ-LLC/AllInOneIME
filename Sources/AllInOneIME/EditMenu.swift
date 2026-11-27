import AppKit

/// The keys every text field answers in an app with a menu bar: an agent app (the input method, `LSUIElement`) has no
/// main menu, so ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z did nothing in Settings' fields (an API key could only be pasted from the context
/// menu). A main menu that is never shown, with an Edit menu of the standard actions sent to the first responder, gives
/// them their keys in every window of ours. Installed once, the first time Settings or the start (its step 3 has a field
/// to type in) opens.
enum EditMenu {
    @MainActor
    static func install() {
        guard NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }
        let edit = NSMenu(title: "Edit")
        // Titles nobody sees (the menu bar of an agent app isn't shown): not translated.
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, modifiers) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)  // no target: the first responder (the field being edited) takes it
        }
        let main = NSApp.mainMenu ?? NSMenu(title: "Main")
        let holder = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        holder.submenu = edit
        main.addItem(holder)
        NSApp.mainMenu = main
    }
}
