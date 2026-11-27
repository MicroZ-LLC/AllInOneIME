import Foundation

/// The patches of the ways typed with a schema and dictionary of their own (Zhuyin's, Wubi's: `ownPatch`), not made from
/// rime-ice's as a Shuangpin scheme's is: `PersonalDictionaryStore` writes them (`<schema>.custom.yaml` in the Rime user
/// folder, this app's marker first, a user's own left alone), the filter of the candidates removed added last.
extension PinyinScheme {
    /// Its patch (`schemaText`: its schema), for `characters`, without the filter of the candidates removed. Zhuyin's: its
    /// characters (its own switch, `ChineseCharacters.patch`), and its translators without rime-ice's custom phrases
    /// (custom_phrase.txt beside them, in pinyin letters and Simplified characters, which its schema would find by Zhuyin's
    /// keys: "u", ㄧ, would offer 有). Wubi's: rime-ice's switch of characters added (its dictionary is in Simplified ones,
    /// `ChineseCharacters.addedSwitchPatch`), and what rime-wubi's schema takes from rime-prelude and rime-pinyin-simp,
    /// which the app hasn't, from rime-ice's data instead (`wubiFromRimeIce`). Both: a tap of Shift commits what is
    /// composed, converted. Not fuzzy pinyin, nor the personal dictionaries (pinyin spellings of rime-ice's dictionary),
    /// nor the shape codes: their keys aren't pinyin. Their own dictionaries learn into their own user dictionaries. Nil
    /// without the schema (nothing to patch), and for the ways that type pinyin (`isPinyin`: rime-ice's patch, made for
    /// their schema).
    func ownPatch(characters: ChineseCharacters, schemaText: String) -> String? {
        guard !isPinyin, !schemaText.isEmpty else { return nil }
        let head = FuzzyPinyin.marker + "\npatch:\n"
        if self == .zhuyin { return head + Self.zhuyinTranslators + Self.shiftCommitsText + (characters.patch(schema: schemaText) ?? "") }
        return head + Self.wubiFromRimeIce + Self.shiftCommitsText + (characters.addedSwitchPatch ?? "")
    }

    /// rime-bopomofo's translators but rime-ice's custom phrases (at the commit the Makefile pins).
    private static let zhuyinTranslators = "  # Without rime-ice's custom phrases (custom_phrase.txt: pinyin letters, which would be Zhuyin keys here).\n"
        + "  engine/translators: [ punct_translator, reverse_lookup_translator, script_translator ]\n"

    /// A tap of Shift: what is composed goes in converted, as macOS's own Zhuyin has it, not the keys typed (rime-ice's
    /// default.yaml: `Shift_L: commit_code`). The schema's map replaces default.yaml's whole: its other keys as rime-ice's.
    private static let shiftCommitsText = "  # A tap of Shift commits what is composed, converted (rime-ice's: the keys typed).\n"
        + "  ascii_composer/switch_key: { Caps_Lock: clear, Shift_L: commit_text, Shift_R: commit_text, Control_L: noop, Control_R: noop }\n"

    /// What rime-wubi's schema (at the commit the Makefile pins) takes from elsewhere, from rime-ice's data, and its keys
    /// as pinyin's are: its punctuation (`import_preset: symbols`, rime-prelude's symbols.yaml) rime-ice's (default.yaml's,
    /// as rime_ice's schema has it); "z" then pinyin looked up (its reverse lookup, `pinyin_simp`'s dictionary)
    /// in rime-ice's dictionary, the one full pinyin types from; ";" punctuation after a code too, not a delimiter. Its
    /// candidate left alone at four codes waits for a pick (`auto_select` off, as its schema has it now), as every way's
    /// does: nothing goes in by itself.
    private static let wubiFromRimeIce = """
          # rime-ice's punctuation, as with pinyin (rime-wubi's is rime-prelude's symbols.yaml, which the app hasn't).
          punctuator/import_preset: default
          # "z" then pinyin: looked up in rime-ice's dictionary (rime-wubi's: rime-pinyin-simp's, which the app hasn't).
          reverse_lookup/dictionary: rime_ice
          # ";" is punctuation after a code too, as with pinyin; a code left with one candidate waits for a pick.
          speller/delimiter: " '"
          speller/auto_select: false

        """
}
