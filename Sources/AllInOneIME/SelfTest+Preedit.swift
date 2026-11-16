import AllInOneIMECore

extension AllInOneIMEInputController {
    /// What is being typed, as the panel's input line shows it (its prompt and text): nothing is marked in the field
    /// (`InputSession+Preedit.swift`), so the self-test reads it here where it read the field's marked text before.
    @MainActor var preedit: String { panelModel().input.map { $0.prompt + $0.text } ?? "" }
}
