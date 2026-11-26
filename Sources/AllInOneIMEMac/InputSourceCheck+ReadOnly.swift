import Carbon
import Foundation

extension InputSourceCheck {
    /// Whether `id` is enabled as itself (`InputSourceState.isEnabled(as:)`) as Text Input Sources has it now, and no
    /// more: nothing registered, nothing waited for, the user's input sources' preferences not synchronized (`isEnabled`
    /// does all three, up to 2 seconds). For looks on the main thread that mustn't hold up typing (the start's step 1, as
    /// the window shows and as each input source is added or taken out); a source not registered yet reads as not added.
    /// Main thread (Text Input Sources).
    public static func isEnabledNow(_ id: String) -> Bool {
        isEnabledNow(id, as: registration(of: id))
    }

    /// `isEnabledNow` with Text Input Sources' answer `state` (`registration`).
    public static func isEnabledNow(_ id: String, as state: InputSourceState) -> Bool {
        state.isEnabled(as: id)
    }

    /// `id` as Text Input Sources has it now: registered, enabled and the bundle ID it is filed under (`state(of:)`
    /// without the user's input sources, `listed` false).
    public static func registration(of id: String) -> InputSourceState {
        let source = source(id)
        return InputSourceState(registered: source != nil, enabled: source.map { bool($0, kTISPropertyInputSourceIsEnabled) } == true,
                                listed: false, bundleID: source.flatMap { string($0, kTISPropertyBundleID) })
    }
}
