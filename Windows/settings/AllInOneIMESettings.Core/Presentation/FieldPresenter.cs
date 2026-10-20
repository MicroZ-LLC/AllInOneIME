using System.Text.Json.Nodes;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Wire;

namespace AllInOneIME.Settings.Presentation;

/// <summary>The control a field is drawn with, from its kind alone (§12.3): no setting is known here.</summary>
public enum FieldControl
{
    /// <summary><c>toggle</c>: a switch.</summary>
    Toggle,
    /// <summary><c>integer</c>: a number box with its bounds and step.</summary>
    NumberBox,
    /// <summary><c>number</c>: a slider; with its <c>status</c> (the value in words).</summary>
    Slider,
    /// <summary>An <c>optional</c> <c>number</c>: a check box that sends it at all, and the slider.</summary>
    OptionalSlider,
    /// <summary><c>text</c>: a box (several lines when <c>multiline</c>), committed on Enter or when focus leaves.</summary>
    TextBox,
    /// <summary><c>text</c> with <c>choices</c>: the box and a menu of suggestions.</summary>
    TextWithSuggestions,
    /// <summary><c>choice</c>: a drop-down.</summary>
    ComboBox,
    /// <summary><c>choices</c>, not ordered: a check box each.</summary>
    CheckList,
    /// <summary><c>choices</c>, <c>ordered</c>: the picked ones in their order (move up, down, remove), and one to add.</summary>
    OrderedList,
    /// <summary><c>words</c>: the line they make (<c>text</c>).</summary>
    Words,
    /// <summary><c>secret</c>: its state (<c>status</c>), a password box and Save; Remove when it has the action.</summary>
    Secret,
    /// <summary><c>items</c>: the list, each with its actions and own fields; the field's actions (add, new, browse).</summary>
    Items,
    /// <summary><c>info</c>: text to read and copy.</summary>
    Info,
    /// <summary><c>button</c>: its action (a box for its value when the action takes a text, <c>textActions</c>), its
    /// last outcome; a progress ring and Cancel while it runs.</summary>
    Button,
    /// <summary>A kind a later engine sends: its label and help, read-only.</summary>
    Unknown,
}

/// <summary>
/// What each field is on screen, and the request each thing the user does makes (null: nothing to send, the value is
/// already that). The window (and the tests) go through here, so that the rules for turning a click or a typed line into
/// a <c>settingsSet</c> or <c>settingsAction</c> live in one place.
/// </summary>
public static class FieldPresenter
{
    public static FieldControl ControlFor(Field field) => field.Kind switch
    {
        "toggle" => FieldControl.Toggle,
        "integer" => FieldControl.NumberBox,
        "number" => field.Optional ? FieldControl.OptionalSlider : FieldControl.Slider,
        "text" => field.Choices.Count > 0 ? FieldControl.TextWithSuggestions : FieldControl.TextBox,
        "choice" => FieldControl.ComboBox,
        "choices" => field.Ordered ? FieldControl.OrderedList : FieldControl.CheckList,
        "words" => FieldControl.Words,
        "secret" => FieldControl.Secret,
        "items" => FieldControl.Items,
        "info" => FieldControl.Info,
        "button" => FieldControl.Button,
        _ => FieldControl.Unknown,
    };

    /// <summary>Whether the control goes under the label, the width of the card (lists, several lines, a key's box),
    /// rather than beside it.</summary>
    public static bool IsWide(Field field) => ControlFor(field) switch
    {
        FieldControl.CheckList or FieldControl.OrderedList or FieldControl.Items or FieldControl.Secret or FieldControl.Words
            or FieldControl.Info or FieldControl.TextWithSuggestions => true,
        FieldControl.TextBox => field.Multiline || field.Picker is not null || (field.StringValue?.Length ?? 0) > 40,
        FieldControl.Button => TakesText(field, MainAction(field)),
        _ => false,
    };

    /// <summary>The name a screen reader says for the field's control: its label; a note without one (the command
    /// editor's warning), its text.</summary>
    public static string AccessibleName(Field field) =>
        field.Label.Length > 0 ? field.Label : field.StringValue ?? field.Value?.ToJsonString() ?? field.Id;

    /// <summary>A value as text (a choice's, for an automation id or a box): a string as it is, anything else as JSON,
    /// so that a later engine's number never throws.</summary>
    public static string ValueText(JsonNode? value) => SettingsDocument.Text(value) ?? value?.ToJsonString() ?? "";

    /// <summary>Whether the user may change it now: not read-only, and the config file can be read.</summary>
    public static bool IsEnabled(Field field, SettingsDocument document) => !field.ReadOnly && document.LoadError is null;

    // MARK: Changes

    public static SettingsSetRequest? Toggled(Field field, bool on) =>
        field.BoolValue == on ? null : new SettingsSetRequest(field.Id, JsonValue.Create(on));

    /// <summary>A whole number typed or stepped to (rounded; the engine checks the bounds and says why).</summary>
    public static SettingsSetRequest? Integer(Field field, double value)
    {
        if (double.IsNaN(value)) return null;
        var whole = Math.Round(value);
        return field.NumberValue == whole ? null : new SettingsSetRequest(field.Id, JsonValue.Create(whole));
    }

    /// <summary>A slider moved to <paramref name="value"/> (rounded to its step).</summary>
    public static SettingsSetRequest? Number(Field field, double value)
    {
        if (double.IsNaN(value)) return null;
        if (field.Step is double step and > 0)
        {
            var from = field.Min ?? 0;
            value = Math.Round(from + Math.Round((value - from) / step) * step, 10);
        }
        return field.NumberValue == value ? null : new SettingsSetRequest(field.Id, JsonValue.Create(value));
    }

    /// <summary>An optional number turned on (at <paramref name="value"/>) or off (null).</summary>
    public static SettingsSetRequest? OptionalNumber(Field field, bool on, double value)
    {
        if (!on) return field.Value is null ? null : new SettingsSetRequest(field.Id, null);
        return field.Value is null ? new SettingsSetRequest(field.Id, JsonValue.Create(value)) : Number(field, value);
    }

    /// <summary>A text committed (Enter, or focus left): empty is null for an optional one.</summary>
    public static SettingsSetRequest? Text(Field field, string text)
    {
        if (text == (field.StringValue ?? "")) return null;
        return new SettingsSetRequest(field.Id, text.Length == 0 && field.Optional ? null : JsonValue.Create(text));
    }

    /// <summary>The <paramref name="index"/>-th of the field's choices picked.</summary>
    public static SettingsSetRequest? Picked(Field field, int index)
    {
        if (index < 0 || index >= field.Choices.Count) return null;
        var choice = field.Choices[index];
        if (choice.Disabled || choice.Is(field.Value)) return null;
        return new SettingsSetRequest(field.Id, choice.Value?.DeepClone());
    }

    /// <summary>The index of the choice that is the value now (-1: none).</summary>
    public static int SelectedChoice(Field field)
    {
        for (var i = 0; i < field.Choices.Count; i++)
        {
            if (field.Choices[i].Is(field.Value)) return i;
        }
        return -1;
    }

    /// <summary>The values picked in a <c>choices</c> field, in its order.</summary>
    public static IReadOnlyList<JsonNode?> PickedValues(Field field) => (field.Value as JsonArray)?.ToList() ?? [];

    /// <summary>Whether the <paramref name="index"/>-th choice is among the values (a check list's box).</summary>
    public static bool IsPicked(Field field, int index) =>
        PickedValues(field).Any(value => JsonNode.DeepEquals(value, field.Choices[index].Value));

    /// <summary>A list changed: the edit, with the list as the window showed it (<c>shown</c>), so that what was added
    /// or taken out elsewhere meanwhile stays so (§12.4).</summary>
    static SettingsSetRequest ListEdit(Field field, JsonNode edited) =>
        new(field.Id, edited, shown: field.Value?.DeepClone() ?? new JsonArray());

    /// <summary>A check list's box checked or cleared: the values in the choices' order.</summary>
    public static SettingsSetRequest? Checked(Field field, int index, bool on)
    {
        if (index < 0 || index >= field.Choices.Count || IsPicked(field, index) == on) return null;
        var values = new JsonArray();
        for (var i = 0; i < field.Choices.Count; i++)
        {
            if (i == index ? on : IsPicked(field, i)) values.Add(field.Choices[i].Value?.DeepClone());
        }
        return ListEdit(field, values);
    }

    /// <summary>An ordered list's entry moved by <paramref name="delta"/> places.</summary>
    public static SettingsSetRequest? Moved(Field field, int position, int delta)
    {
        var values = PickedValues(field).Select(v => v?.DeepClone()).ToList();
        var to = position + delta;
        if (position < 0 || position >= values.Count || to < 0 || to >= values.Count) return null;
        (values[position], values[to]) = (values[to], values[position]);
        return ListEdit(field, new JsonArray([.. values]));
    }

    /// <summary>An ordered list's entry removed.</summary>
    public static SettingsSetRequest? Removed(Field field, int position)
    {
        var values = PickedValues(field).Select(v => v?.DeepClone()).ToList();
        if (position < 0 || position >= values.Count) return null;
        values.RemoveAt(position);
        return ListEdit(field, new JsonArray([.. values]));
    }

    /// <summary>The choices an ordered list can add: not in it, not disabled.</summary>
    public static IReadOnlyList<Choice> Addable(Field field) =>
        field.Choices.Where(c => !c.Disabled && !PickedValues(field).Any(v => JsonNode.DeepEquals(v, c.Value))).ToList();

    /// <summary>A choice added at the end of an ordered list.</summary>
    public static SettingsSetRequest? Added(Field field, Choice choice)
    {
        var values = PickedValues(field).Select(v => v?.DeepClone()).ToList();
        if (values.Any(v => JsonNode.DeepEquals(v, choice.Value))) return null;
        values.Add(choice.Value?.DeepClone());
        return ListEdit(field, new JsonArray([.. values]));
    }

    /// <summary>The label a value of the field has (its choice's), or the value itself.</summary>
    public static string LabelOf(Field field, JsonNode? value) => field.Choices.FirstOrDefault(c => c.Is(value))?.Label ?? ValueText(value);

    /// <summary>A words field's line as shown: its <c>text</c>, else the words with ", " between them.</summary>
    public static string WordsLine(Field field) => field.Text ?? string.Join(", ", field.StringsValue);

    /// <summary>A words field's line committed: sent as the line (the engine splits it as it shows it), with the line
    /// it showed (<c>shown</c>: words added elsewhere meanwhile stay; a command line changed elsewhere is <c>stale</c>);
    /// or as the words split at commas for an engine without <c>text</c>, with the words shown.</summary>
    public static SettingsSetRequest? Words(Field field, string line)
    {
        if (line == WordsLine(field)) return null;
        if (field.Text is not null) return new SettingsSetRequest(field.Id, JsonValue.Create(line), shown: JsonValue.Create(field.Text));
        var words = line.Split([',', '，', '、', ';', '；', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        return ListEdit(field, new JsonArray([.. words.Select(w => (JsonNode?)JsonValue.Create(w))]));
    }

    // MARK: Actions

    /// <summary>A key, token or password saved: once, to the engine. Nothing for an empty box.</summary>
    public static SettingsActionRequest? SaveSecret(Field field, string key) =>
        string.IsNullOrWhiteSpace(key) || !field.Actions.Contains("setKey") ? null : new SettingsActionRequest(field.Id, "setKey", key: key);

    public static SettingsActionRequest? RemoveSecret(Field field) =>
        field.Actions.Contains("removeKey") ? new SettingsActionRequest(field.Id, "removeKey") : null;

    /// <summary>A button's action (its first; <c>cancel</c> is its own button while it runs).</summary>
    public static string? MainAction(Field field) => field.Actions.FirstOrDefault(a => a != "cancel");

    /// <summary>Whether <paramref name="action"/> takes a text the user types (<c>textActions</c>).</summary>
    public static bool TakesText(Field field, string? action) => action is not null && field.TextActions.Contains(action);

    /// <summary>A button's action, with the value typed beside it (a link to test) when it takes one.</summary>
    public static SettingsActionRequest? Run(Field field, string? value = null) => MainAction(field) is not { } action ? null
        : new SettingsActionRequest(field.Id, action, value: !TakesText(field, action) || string.IsNullOrWhiteSpace(value) ? null
                                                                 : JsonValue.Create(value.Trim()));

    /// <summary>Whether an action that takes a while runs on the field (or on <paramref name="item"/>): its progress and
    /// Cancel are shown.</summary>
    public static bool IsRunning(Field field, Item? item = null) =>
        item is null ? field.Running && field.Actions.Contains("cancel") : item.Running && item.Actions.Contains("cancel");

    /// <summary><c>cancel</c>: what runs on the field (or on the item: an install) stopped.</summary>
    public static SettingsActionRequest? Cancel(Field field, Item? item = null) =>
        IsRunning(field, item) ? new SettingsActionRequest(field.Id, "cancel", item: item?.Id) : null;

    /// <summary>An item's action: remove a plugin, an app, a folder; delete a command; install from the library.</summary>
    public static SettingsActionRequest ItemAction(Field field, Item item, string action) => new(field.Id, action, item: item.Id);

    /// <summary>A field's own action that takes nothing (browse the library).</summary>
    public static SettingsActionRequest FieldAction(Field field, string action) => new(field.Id, action);

    /// <summary>An app or a folder added by what was typed or picked.</summary>
    public static SettingsActionRequest? Add(Field field, string value) =>
        string.IsNullOrWhiteSpace(value) || !field.Actions.Contains("add") || !TakesText(field, "add") ? null
            : new SettingsActionRequest(field.Id, "add", value: JsonValue.Create(value.Trim()));

    /// <summary>The field's actions that a list shows as its own buttons: not one that takes a text (it has its own box:
    /// <c>add</c>), nor <c>cancel</c> (shown while one runs). <c>save</c> opens the editor.</summary>
    public static IReadOnlyList<string> ListActions(Field field) =>
        field.Actions.Where(a => !TakesText(field, a) && a != "cancel").ToList();

    /// <summary>An item's own buttons: its actions but <c>cancel</c> (shown while one runs on it).</summary>
    public static IReadOnlyList<string> ItemActions(Item item) => item.Actions.Where(a => a != "cancel").ToList();

    // MARK: The editor of an items field's values (a custom command's: its schema)

    /// <summary>What the editor shows first: an item's value's keys, or each schema field's own value (a new one). A
    /// command line (<c>words</c>) as the one line it is typed as; a note (<c>info</c>) is no value.</summary>
    public static Dictionary<string, JsonNode?> FormValues(Field field, Item? item)
    {
        var values = new Dictionary<string, JsonNode?>();
        var definition = item?.Value as JsonObject;
        foreach (var form in field.Schema.Where(f => f.Kind != "info"))
        {
            if (definition is null)
            {
                values[form.Id] = form.Kind == "words" ? JsonValue.Create(form.Text ?? "") : form.Value?.DeepClone();
                continue;
            }
            var value = definition[form.Id];
            values[form.Id] = form.Kind == "words" && value is JsonArray words
                ? JsonValue.Create(CommandLine(words.Select(w => SettingsDocument.Text(w) ?? "")))
                : value?.DeepClone();
        }
        return values;
    }

    /// <summary>Whether a schema's field applies with the editor's values as they are (its <c>when</c>).</summary>
    public static bool IsShown(Field form, IReadOnlyDictionary<string, JsonNode?> values) =>
        form.When.All(rule => rule.Value.Any(v => JsonNode.DeepEquals(v, values.GetValueOrDefault(rule.Key))));

    /// <summary>The editor saved: the item's value (or a new one) with the values of the schema's fields that apply; the
    /// keys the schema doesn't name (an icon, a color) sent back as they were. Left out: a field that doesn't apply, a
    /// note, a text left empty, a number not set, an optional switch that is off.</summary>
    public static SettingsActionRequest SaveForm(Field field, Item? item, IReadOnlyDictionary<string, JsonNode?> values)
    {
        var definition = (item?.Value as JsonObject)?.DeepClone() as JsonObject ?? [];
        foreach (var form in field.Schema)
        {
            definition.Remove(form.Id);
            if (form.Kind == "info" || !IsShown(form, values)) continue;
            var value = values.GetValueOrDefault(form.Id);
            if (value is null || value is JsonValue v && (SettingsDocument.Text(v) is { } text && text.Trim().Length == 0
                    || form.Kind == "toggle" && form.Optional && SettingsDocument.Bool(v) == false)) continue;
            definition[form.Id] = value.DeepClone();
        }
        return new SettingsActionRequest(field.Id, "save", item: item?.Id, value: definition);
    }

    /// <summary>A program and its arguments as one line, as the core writes it for Windows (<c>CustomCommand.commandLine</c>
    /// with its Windows rules), which the engine splits back with <c>CommandLineToArgvW</c>'s: an argument with a space, a
    /// tab or a <c>"</c> (or none at all) in quotes, its <c>"</c> and the backslashes before one escaped; a path's
    /// backslashes as they are (<c>C:\Tools\run.exe</c>).</summary>
    public static string CommandLine(IEnumerable<string> argv) => string.Join(" ", argv.Select((argument, index) =>
    {
        if (argument.Length > 0 && !argument.Any(c => c is ' ' or '\t' or '\n' or '\v' or '"')) return argument;
        // The program: in quotes as it is (a file name has no ").
        if (index == 0) return "\"" + argument + "\"";
        var line = new System.Text.StringBuilder("\"");
        var backslashes = 0;
        foreach (var c in argument)
        {
            if (c == '\\')
            {
                backslashes++;
            }
            else
            {
                // n backslashes before a " become 2n + 1: the " escaped.
                if (c == '"') line.Append('\\', backslashes + 1);
                backslashes = 0;
            }
            line.Append(c);
        }
        // n backslashes before the closing " become 2n.
        return line.Append('\\', backslashes).Append('"').ToString();
    }));
}
