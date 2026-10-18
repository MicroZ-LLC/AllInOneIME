# iCloud sync: app-level regression cases (for `make selftest`)

From the re-check of 2026-10-17 (icloud-recheck-20261017.md). These cases are in Settings' save logic in
Sources/AllInOneIME, so the core tests can't reach them. Written by the independent test author. The implementer turns
each case into a `make selftest` check (e.g. in SettingsWritesSelfTest.swift or ICloudSyncSelfTest.swift) and keeps
the setup, steps and expected result as written here. The implementer may not weaken a case. If the logic isn't
reachable from a self-test, it may be moved into a function the view calls (for example, the words field's save taking
the model, the field's text and the list it showed). The check must then drive that same function, the one that
`onSubmit`, `onDisappear`, the editor's Save and the Delete dialog use.

Shared setup for every case:
- A temporary config.json, never ~/.config/allinoneime.
- A `SettingsModel(configURL:)` on it, as the Settings window holds it.
- "Sync writes the file" means config.json is rewritten as a sync run writes it: `ICloudSync.writeConfig` or
  `AIConfig.writing` with only the keys sync brought, and a new modification time.
- "The model reloads" means `model.reloadIfChanged()` is called, which is what `.allInOneIMEConfigChanged` does.
- "The model misses the reload" means it is not called. This is the window's `.receive(on: RunLoop.main)` delivery
  postponed by a slider drag or an open menu.

The pass condition reads config.json from disk after the save, not only the model. A sync run would put that file in
iCloud.

---

## S33: hidden words saved from a field whose model missed a sync reload

The current `PrivacySection.saveWords` applies the field's edit to the list in the model. If the model missed the reload
that brought in another Mac's word, the save writes the stale list and the synced word is lost on every Mac.

**Setup**
1. config.json has `redaction.enabled = true`, `redaction.customWords = ["Acme"]`, and `iCloudSync.hiddenWords = true`.
2. The model is made on it. Settings → AI Provider → Privacy is shown, so the words field reads `Acme` and the list it
   showed is `["Acme"]`.

**Steps**
1. Sync writes the file: `redaction.customWords = ["Acme", "Project Phoenix"]`. This is another Mac's new hidden word.
2. The model misses the reload. `model.config.redaction.customWords` is still `["Acme"]`.
3. The user edits the words field to `Acme, Bolt`, so it counts as edited.
4. The user presses Return in the field (`onSubmit`). Run it again with the user leaving the page instead
   (`onDisappear`). Both go through `saveWords`.

**Expected**
- config.json's `redaction.customWords` holds exactly `Acme`, `Project Phoenix` and `Bolt`, each once. Order is free.
- `model.config.redaction.customWords` is the same list.
- The field then shows those three words.
- Two more variants pass too:
  - Step 3 removes a word: the field becomes `Bolt`. The file then holds `Project Phoenix` and `Bolt`, not `Acme`.
    `Project Phoenix` is never dropped.
  - The model does reload at step 2. The result is the same as in the main case. This is the probe's D33, which
    passes today and must keep passing.
- The rest of the file is unchanged: the other redaction switches and the keys outside `redaction`.

---

## S34: editing a command by index after another Mac deleted an earlier one

The command editor saves with `model.config.customCommands[index] = command`. Its name check excludes `others` by
offset. The Delete dialog removes by index. When a sync reload changes the list while the editor or the dialog is open,
the index points at a different command. All four cases share this setup:

**Setup**
1. config.json has `customCommands = [alpha, beta, gamma]`, three prompt commands with prompts `do alpha`, `do beta`
   and `do gamma`.
2. The model is made on it, and the Commands page is shown.

The editor is opened by the page's own Edit button (`CommandEdit(index:command:)` with the index the list showed). The
editor is saved through the same closure the sheet uses.

### S34: same name, new prompt

**Steps**
1. Open the editor on `beta`, index 1.
2. Sync writes the file: `customCommands = [beta, gamma]` (another Mac deleted `alpha`). The model reloads.
3. In the editor, change beta's prompt to `do beta better`, keep its name, and save.

**Expected**
- The editor accepts the save. It shows no "Another command has this name" error, because the only `beta` is the one
  being edited.
- config.json holds exactly `[beta (prompt "do beta better"), gamma (prompt "do gamma")]`.
- `gamma` is kept. Nothing named `alpha` comes back.

### D34b: the edited command was deleted elsewhere meanwhile

**Steps**
1. Open the editor on `alpha`, index 0.
2. Sync writes the file: `customCommands = [beta, gamma]` (another Mac deleted `alpha`). The model reloads.
3. In the editor, change alpha's prompt to `do alpha better` and save.

**Expected**
- `beta` and `gamma` are both kept with their prompts. `beta` is never overwritten.
- The edited command is added back as a new command, since it is no longer in the list: config.json holds exactly
  `beta`, `gamma` and `alpha (prompt "do alpha better")`.

### D34c: rename while an earlier command is deleted elsewhere

**Steps**
1. Open the editor on `beta`, index 1.
2. Sync writes the file: `customCommands = [beta, gamma]`. The model reloads.
3. In the editor, rename `beta` to `delta`, keep the prompt `do beta`, and save.

**Expected**
- config.json holds exactly `[delta (prompt "do beta"), gamma (prompt "do gamma")]`.
- `gamma` is kept, and no command named `beta` is left.

### D34e: rename of the last command when its index is gone (no crash)

**Steps**
1. Open the editor on `gamma`, index 2 (the last one).
2. Sync writes the file: `customCommands = [beta, gamma]`. The model reloads, so index 2 no longer exists.
3. In the editor, rename `gamma` to `omega` and save.

**Expected**
- No crash. Settings runs inside the input method's process, so a crash here takes the input method down. The self-test
  process must still be running after the save, and the check after the save must run.
- config.json holds exactly `[beta (prompt "do beta"), omega (prompt "do gamma")]`. `gamma` is renamed in place, not
  kept beside `omega`, and `beta` is untouched.
- The name check for this edit is done against `[beta]`. `gamma` doesn't count as another command, since it is the one
  being edited.

### S34-delete: the Delete dialog after an earlier command is deleted elsewhere

The Delete dialog also works by index (`commandToDelete`), so it gets the same check.

**Steps**
1. Press Delete on `gamma`, index 2. The dialog shows `@gamma`.
2. Sync writes the file: `customCommands = [beta, gamma]`. The model reloads.
3. Confirm the delete.

**Expected**
- No crash.
- config.json holds exactly `[beta]`: `gamma`, the one the user confirmed, is gone and `beta` is kept.
- Run it again with Delete pressed on `beta` (index 1) at step 1. The result must be `[gamma]`, never `[beta]`.
