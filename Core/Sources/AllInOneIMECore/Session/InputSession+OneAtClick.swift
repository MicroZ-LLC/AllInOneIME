import Foundation

extension InputSession {
    /// A click on one @'s row that nothing picks but says why (`PanelModel.Row.saysWhy`: an AI command where AI isn't
    /// used): what ⏎ on it does, the notice, the draft and the list as they were (`Composer.oneAtClicked`), as the keys
    /// and a click do the same everywhere. False: not such a row (the click goes on to what it picks).
    func oneAtSaidWhy(_ row: Int) -> Bool {
        let rows = panelModel().rows
        guard rows.indices.contains(row), rows[row].saysWhy else { return false }
        perform(composer.oneAtClicked(row))
        return true
    }
}
