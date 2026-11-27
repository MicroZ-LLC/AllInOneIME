import AllInOneIMECore
import SwiftUI

/// Settings → AI, choosing (Change ▾; 0.7.4's design, #174): Cancel at the top right, then every choice as a card, by
/// how it connects (`AIPickerState`, kept as `SettingsModel.aiCards`); one click on a card chooses it and collapses the
/// page. A CLI's card says whether it is installed and signed in, as last looked at: the CLIs are looked at as the cards
/// show (`SettingsModel.aiPageShown`; collapsed, only the one in use is), each as last found unless that is too old
/// (`ClaudeSessionMac.checkAvailability`: its program runs only then).
struct AIChoiceSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let facts = model.aiFacts
        let cards = model.aiCards
        AIChoicesGrid(chosen: cards.chosen, groups: cards.visibleGroups,
                      status: { facts.status($0, config: model.config) }, pick: choose, cancel: collapse)
        .padding(.vertical, 6)
        .settingsRow(.provider, shown: model.spot)
        .onAppear { model.aiPageShown() }
        // Collapsed as the page goes (another page, the window closed) and as a new window starts, opened again, so that
        // the page comes back collapsed, unless the window is pointed at the cards (`SettingsModel.point`).
        .onDisappear { model.changeAICards { $0.pageLeft() } }
        .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESettingsReopened)) { _ in
            if model.spot != .provider { model.changeAICards { $0.pageLeft() } }
        }
    }

    /// Cancel, or Esc: collapsed, nothing chosen.
    private func collapse() {
        withAnimation(.easeOut(duration: 0.15)) { model.changeAICards { $0.cancel() } }
        if model.spot == .provider { model.spot = nil }
    }

    /// A card clicked: chosen (`SettingsModel.choose`), the page collapsed.
    private func choose(_ choice: AIChoice) {
        model.choose(choice)
        withAnimation(.easeOut(duration: 0.15)) { model.changeAICards { $0.pick(choice) } }
        if model.spot == .provider { model.spot = nil }
    }
}

/// Settings → AI's section title, with what the choice is for at the right (`SettingsSpot.providerNote`).
struct AISectionHeader: View {
    let cli: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionTitle(tr("AI", "AI"), icon: CommandIcons.provider)
            Spacer()
            Text(SettingsSpot.providerNote(cli: cli)).font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension SettingsModel {
    /// Whether the provider's key is set, as its row shows it and as a request finds it (`APIKeys.load(_:for:)`): one in
    /// the shell only for a base URL it is sent to (`APIKeys.shellKeyGoes`), one saved only for the host it was saved
    /// for (`keyHosts`: a base URL changed to another service's doesn't get it, and nothing here says it is set).
    func keyState(_ provider: Provider) -> KeyState {
        let host = HTTPProviders.host(of: config.settings(for: provider))
        return KeyState(keySources[provider]?.sent(by: provider, to: host, savedFor: keyHosts[provider]), ending: keyEndings[provider])
    }

    /// False for previews/screenshots: nothing is ever written.
    var persists: Bool { store.persists }

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

    /// Settings → AI shown, collapsed or choosing (the page come to, Change ▾, Cancel): the sign-in of each CLI among
    /// the choices shown (collapsed, the one in use; choosing, every card's) looked at, as last found unless that is too
    /// old (a signed-in one kept until quit, the others for `ClaudeSessionManager.recheckInterval`): shown again within
    /// it, nothing runs. Never at launch or while typing; a preview shows what it was given.
    func aiPageShown() {
        let cards = aiCards
        let agents = (cards.choosing ? cards.visibleGroups.flatMap(\.choices) : [cards.chosen]).compactMap(\.agent)
        if let cliChecks { cliChecks(agents) } else { refreshSessions(agents) }
    }

    /// Settings → AI as the page shows it now: `aiPicker` (collapsed or choosing, the card pointed at) with the AI
    /// chosen and the choices offered now.
    var aiCards: AIPickerState {
        var cards = aiPicker
        cards.update(chosen: config.ai, groups: AIChoice.groups(apple: aiFacts.apple, keeping: config.ai))
        return cards
    }

    /// `change` made to Settings → AI's cards as they are now (`aiCards`): Change ▾, Cancel or a card clicked, the page shown.
    func changeAICards(_ change: (inout AIPickerState) -> Void) {
        var cards = aiCards
        change(&cards)
        aiPicker = cards
    }

    /// The window pointed at `spot` (`SettingsWindow.show(page:spot:card:)`, the settings search's row), outlined on its
    /// page; with no spot, a `card` (the Doctor's) points at Settings → AI's choices, unless it is the one in use (its own
    /// rows are at the top). Pointed at them, the choices open, scrolled to `card` (the start's, the Doctor's) or to
    /// a choice `search` names (what the search had typed: "kiro"), unless that one is in use, at the top.
    func point(at spot: SettingsSpot?, search: String? = nil, card: AIChoice? = nil) {
        pointNow(at: spot, search: search, card: card)
        guard card != nil else { return }
        // A card is compared with the AI in use as the file has it now: a change just written (the Assistant's) may not
        // have reached the model yet, and the card it points at is then the one in use, not one to open the choices for.
        // The file is read off the main thread (`reloadIfChangedOffMain`); where it has another AI in use, the window
        // still pointed as it was a moment ago is pointed again, from the page collapsed.
        let (pointed, inUse) = (self.spot, config.ai)
        reloadIfChangedOffMain { [weak self] in
            guard let self, config.ai != inUse, self.spot == pointed else { return }
            changeAICards { $0.show(search: nil, target: nil) }
            pointNow(at: spot, search: search, card: card)
        }
    }

    /// `point`, with the settings as the model has them now.
    private func pointNow(at spot: SettingsSpot?, search: String?, card: AIChoice?) {
        let spot = spot ?? card.flatMap { $0 == config.ai ? nil : SettingsSpot.provider }
        // Pointed anywhere else (another row, the card in use), the page is collapsed: the chosen AI's rows show only then.
        let cards = spot == .provider
        if cards || spot != nil || card != nil { changeAICards { $0.show(search: cards ? search : nil, target: cards ? card : nil) } }
        self.spot = spot
    }

    /// What the window scrolls to for `spot`, in turn (`SettingsView.scroll`), and scrolls to again as it changes: its
    /// row; on Settings → AI's choices, then the card pointed at, the choices open (`AIPickerState.scrollTarget`).
    var spotIDs: [AnyHashable] {
        guard let spot else { return [] }
        let card = spot == .provider ? aiPicker.scrollTarget : nil
        return [AnyHashable(spot.row)] + (card.map { [AnyHashable($0)] } ?? [])
    }

    /// Looks whether each CLI is installed and signed in (`ClaudeSessionMac.checkAvailability`: as last found unless that
    /// is too old; `force`: each one's program run now), then shows it. A preview shows what it was given: nothing of this
    /// Mac's.
    /// The CLI picked as the AI, shown again (the start's step 2 come back to, after picking it in Settings or signing in
    /// in Terminal): its sign-in looked at again while it isn't ready, so that the step moves on once it is. Still only as
    /// a CLI is picked: nothing is looked at for another AI, nor at launch.
    func pickedCLIShownAgain() {
        guard let agent = config.ai.agent, !aiFacts.status(.cli(agent), config: config).isReady else { return }
        refreshSessions([agent], force: true)
    }

    func refreshSessions(_ agents: [SessionAgent] = SessionAgent.allCases, force: Bool = false) {
        guard persists, !agents.isEmpty else { return }
        ClaudeSessionMac.checkAvailability(agents, force: force) { [weak self] in
            self?.sessionAvailability = ClaudeSessionMac.managers.mapValues(\.availability)
        }
    }
}
