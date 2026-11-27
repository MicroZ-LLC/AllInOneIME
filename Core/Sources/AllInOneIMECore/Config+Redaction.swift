extension Config {
    /// These settings with sensitive information hidden from the AI, every detector on: what a new install starts
    /// with (`Config.fresh`).
    var hidingSensitiveInformation: Config {
        var config = self
        config.redaction.enabled = true
        return config
    }
}
