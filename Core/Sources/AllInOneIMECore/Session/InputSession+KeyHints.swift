import Foundation

extension InputSession {
    /// A panel of the session's own (clipboard history, suggestion rows) as Settings → Input → Show key hints says
    /// (`Config.keyHints`): off, without its keys (`PanelModel.withoutKeyHints`), as the composer's panel is
    /// (`PanelPresenter.model(for:)`). One switch for every panel.
    func keyHinted(_ model: PanelModel) -> PanelModel {
        services.loadSettings().keyHints ? model : model.withoutKeyHints
    }
}
