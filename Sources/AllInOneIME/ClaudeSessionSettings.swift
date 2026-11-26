import AllInOneIMECore
import SwiftUI

/// Settings → AI's choices (`Config.ai`, the owner's design; #121, #161): the one in use as a card, outlined, then the
/// others folded under one row (`AIPickerState`, kept as `SettingsModel.aiCards`), folded each time the page shows; one
/// click on a card chooses it and folds them again. A CLI's card says whether it is installed and signed in, as last
/// looked at: a CLI is looked at as its card shows (`SettingsModel.aiCardsShown`: the one in use as the page shows, the
/// others as they unfold), each as last found unless that is too old (`ClaudeSessionMac.checkAvailability`: its program
/// runs only then), so a folded list runs nothing.
struct AIChoiceSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let facts = model.aiFacts
        let cards = model.aiCards
        let status = { (choice: AIChoice) in facts.status(choice, config: model.config) }
        VStack(alignment: .leading, spacing: 12) {
            // As wide as the cards under the row.
            LazyVGrid(columns: AIChoicesGrid.columns, alignment: .leading, spacing: 10) {
                AIChoiceCard(choice: cards.chosen, status: status(cards.chosen), chosen: true) { choose(cards.chosen) }
                    .id(cards.chosen)  // a card pointed at, in use
                    .onAppear { model.aiCardsShown([cards.chosen]) }
            }
            DisclosureGroup(isExpanded: Binding(get: { cards.isExpanded },
                                                set: { open in model.changeAICards { if $0.isExpanded != open { $0.toggle() } } })) {
                AIChoicesGrid(chosen: cards.chosen, groups: cards.otherGroups, status: status, pick: choose)
                    .onAppear { model.aiCardsShown(cards.otherGroups.flatMap(\.choices)) }
            } label: {
                Text(cards.rowTitle)
            }
            .disclosureGroupStyle(RowDisclosureStyle())
        }
        .padding(.vertical, 6)
        .settingsRow(.provider, shown: model.spot)
        // Folded as the page shows, and as a new window starts, opened again (`SettingsView`'s own state is reset the
        // same way).
        .onAppear(perform: shown)
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESettingsReopened)) { _ in shown() }
        // Folded as the page goes too: shown again (another page, the window closed), it must not unfold for a moment and
        // look at the other CLIs' sign-ins before `shown` folds it.
        .onDisappear { model.changeAICards { $0.show(search: nil, target: nil) } }
    }

    /// The page shown, or the window opened again: the others folded, unless the window is pointed at the cards
    /// (`SettingsModel.point`, which unfolds them as it needs).
    private func shown() {
        if model.spot != .provider { model.changeAICards { $0.show(search: nil, target: nil) } }
    }

    /// A card clicked: chosen (`SettingsModel.choose`), the others folded again.
    private func choose(_ choice: AIChoice) {
        model.changeAICards { $0.pick(choice) }
        model.choose(choice)
        if model.spot == .provider { model.spot = nil }
    }
}

extension SettingsModel {
    /// What this Mac has, for each choice's status (`AIFacts`): the CLIs' sign-ins, the keys as their rows show them,
    /// AllInOneIME Cloud's sign-in, the AWS profiles with their regions and kinds, Apple's model.
    var aiFacts: AIFacts {
        let keyed: [Provider] = [.anthropic, .gemini, .openai]
        return AIFacts(sessions: sessionAvailability,
                       keys: Dictionary(uniqueKeysWithValues: keyed.map { ($0, keyState($0)) }),
                       hostedSignedIn: account != nil || keyState(.hosted).isSet,
                       // As read in the background (`AWSProfileModel.refresh`); until then Bedrock's card says "Checking…".
                       awsProfiles: aws.requestProfiles,
                       apple: AppleModel.system.availability)
    }

    /// The settings as what has to be fast goes with them (autocomplete's row): with a CLI chosen, its fast fallback by
    /// `aiFacts` as the provider (`Config.fastConfig`, which the input menu and the menu bar panel go by too); nil: there
    /// is none.
    var fastConfig: Config? { config.fastConfig(aiFacts) }

    /// The AI chosen (`Config.ai`), saved: a provider is set as the provider and no CLI is (`cli`); a CLI is set, the
    /// provider kept as it was (the fast fallback, `Config.fastProvider`).
    func choose(_ choice: AIChoice) {
        if let provider = choice.provider { config.provider = provider }
        cli.wrappedValue = choice.agent.map(QuestionBackend.init)
    }

    /// The CLI chosen as the AI (`Config.questionBackend`; nil: the provider is), saved as it is set. Another one than
    /// before (or none) ends every session's process: the next question starts the one chosen. A CLI chosen, each one's
    /// sign-in is looked at again (`refreshSessions`).
    var cli: Binding<QuestionBackend?> {
        Binding(get: { self.config.questionBackend }, set: { backend in
            let before = self.config.questionSessionAgent
            self.config.questionBackend = backend
            self.save()
            guard self.persists, self.config.questionSessionAgent != before else { return }
            for session in ClaudeSessionMac.managers.values { session.stop() }  // the next question starts the one chosen
            if backend != nil { self.refreshSessions() }
        })
    }

    /// Settings → AI's cards `choices` shown (the one in use as the page shows, the others as they unfold): the sign-in of
    /// each CLI among them looked at for its card, as last found unless that is too old (a signed-in one kept until quit,
    /// the others for `ClaudeSessionManager.recheckInterval`): shown again within it, nothing runs. Never at launch or
    /// while typing, nor for the cards folded; a preview shows what it was given.
    func aiCardsShown(_ choices: [AIChoice]) { refreshSessions(choices.compactMap(\.agent)) }

    /// Settings → AI's cards as the page shows them now: `aiPicker` (folded or not, the card pointed at) with the AI
    /// chosen and the choices offered now.
    var aiCards: AIPickerState {
        var cards = aiPicker
        cards.update(chosen: config.ai, groups: AIChoice.groups(apple: aiFacts.apple, keeping: config.ai))
        return cards
    }

    /// `change` made to Settings → AI's cards as they are now (`aiCards`): a click on the row or a card, the page shown.
    func changeAICards(_ change: (inout AIPickerState) -> Void) {
        var cards = aiCards
        change(&cards)
        aiPicker = cards
    }

    /// The window pointed at `spot` (`SettingsWindow.show(page:spot:card:)`, the settings search's row), outlined on its
    /// page; with no spot, a `card` (the Doctor's) points at Settings → AI's choices, unless it is the one in use (its own
    /// rows are at the top). Pointed at them, the other cards unfold, scrolled to `card` (the start's, the Doctor's) or to
    /// a choice `search` names (what the search had typed: "kiro"), unless that one is in use, at the top.
    func point(at spot: SettingsSpot?, search: String? = nil, card: AIChoice? = nil) {
        // A card is compared with the AI in use as the file has it now: a change just written (the Assistant's) may not
        // have reached the model yet, and the card it points at is then the one in use, not one to unfold.
        if card != nil { reloadIfChanged() }
        let spot = spot ?? card.flatMap { $0 == config.ai ? nil : SettingsSpot.provider }
        if spot == .provider { changeAICards { $0.show(search: search, target: card) } }
        self.spot = spot
    }

    /// What the window scrolls to for `spot`, in turn (`SettingsView.scroll`), and scrolls to again as it changes: its
    /// row; on Settings → AI's choices, then the card pointed at, unfolded (`AIPickerState.scrollTarget`).
    var spotIDs: [AnyHashable] {
        guard let spot else { return [] }
        let card = spot == .provider ? aiPicker.scrollTarget : nil
        return [AnyHashable(spot.row)] + (card.map { [AnyHashable($0)] } ?? [])
    }

    /// Looks whether each CLI is installed and signed in (`ClaudeSessionMac.checkAvailability`: as last found unless that
    /// is too old; `force`: each one's program run now), then shows it. A preview shows what it was given: nothing of this
    /// Mac's.
    func refreshSessions(_ agents: [SessionAgent] = SessionAgent.allCases, force: Bool = false) {
        guard persists, !agents.isEmpty else { return }
        ClaudeSessionMac.checkAvailability(agents, force: force) { [weak self] in
            self?.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
        }
    }
}
