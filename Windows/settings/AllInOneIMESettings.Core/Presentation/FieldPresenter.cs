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
    /// <summary><c>button</c>: its action (a box for its value when it has a <c>placeholder</c>), its last outcome.</summary>
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
        FieldControl.TextBox => field.Multiline || field.Pick is not null || (field.StringValue?.Length ?? 0) > 40,
        FieldControl.Button => field.Placeholder is not null,
        _ => false,
    };

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

    /// <summary>A check list's box checked or cleared: the values in the choices' order.</summary>
    public static SettingsSetRequest? Checked(Field field, int index, bool on)
    {
        if (index < 0 || index >= field.Choices.Count || IsPicked(field, index) == on) return null;
        var values = new JsonArray();
        for (var i = 0; i < field.Choices.Count; i++)
        {
            if (i == index ? on : IsPicked(field, i)) values.Add(field.Choices[i].Value?.DeepClone());
        }
        return new SettingsSetRequest(field.Id, values);
    }

    /// <summary>An ordered list's entry moved by <paramref name="delta"/> places.</summary>
    public static SettingsSetRequest? Moved(Field field, int position, int delta)
    {
        var values = PickedValues(field).Select(v => v?.DeepClone()).ToList();
        var to = position + delta;
        if (position < 0 || position >= values.Count || to < 0 || to >= values.Count) return null;
        (values[position], values[to]) = (values[to], values[position]);
        return new SettingsSetRequest(field.Id, new JsonArray([.. values]));
    }

    /// <summary>An ordered list's entry removed.</summary>
    public static SettingsSetRequest? Removed(Field field, int position)
    {
        var values = PickedValues(field).Select(v => v?.DeepClone()).ToList();
        if (position < 0 || position >= values.Count) return null;
        values.RemoveAt(position);
        return new SettingsSetRequest(field.Id, new JsonArray([.. values]));
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
        return new SettingsSetRequest(field.Id, new JsonArray([.. values]));
    }

    /// <summary>The label a value of the field has (its choice's), or the value itself.</summary>
    public static string LabelOf(Field field, JsonNode? value) =>
        field.Choices.FirstOrDefault(c => c.Is(value))?.Label ?? (value is JsonValue v && v.TryGetValue<string>(out var s) ? s : value?.ToJsonString() ?? "");

    /// <summary>A words field's line as shown: its <c>text</c>, else the words with ", " between them.</summary>
    public static string WordsLine(Field field) => field.Text ?? string.Join(", ", field.StringsValue);

    /// <summary>A words field's line committed: sent as the line (the engine splits it as it shows it), or as the
    /// words split at commas for an engine without <c>text</c>.</summary>
    public static SettingsSetRequest? Words(Field field, string line)
    {
        if (line == WordsLine(field)) return null;
        if (field.Text is not null) return new SettingsSetRequest(field.Id, JsonValue.Create(line));
        var words = line.Split([',', '，', '、', ';', '；', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        return new SettingsSetRequest(field.Id, new JsonArray([.. words.Select(w => (JsonNode?)JsonValue.Create(w))]));
    }

    // MARK: Actions

    /// <summary>A key, token or password saved: once, to the engine. Nothing for an empty box.</summary>
    public static SettingsActionRequest? SaveSecret(Field field, string key) =>
        string.IsNullOrWhiteSpace(key) || !field.Actions.Contains("setKey") ? null : new SettingsActionRequest(field.Id, "setKey", key: key);

    public static SettingsActionRequest? RemoveSecret(Field field) =>
        field.Actions.Contains("removeKey") ? new SettingsActionRequest(field.Id, "removeKey") : null;

    /// <summary>A button's action, with the value typed beside it (a link to test), if any.</summary>
    public static SettingsActionRequest? Run(Field field, string? value = null) =>
        field.Actions.Count == 0 ? null : new SettingsActionRequest(field.Id, field.Actions[0],
                                                                    value: string.IsNullOrWhiteSpace(value) ? null : JsonValue.Create(value.Trim()));

    /// <summary>An item's action: remove a plugin, an app, a folder; delete a command; install from the library.</summary>
    public static SettingsActionRequest ItemAction(Field field, Item item, string action) => new(field.Id, action, item: item.Id);

    /// <summary>A field's own action that takes nothing (browse the library).</summary>
    public static SettingsActionRequest FieldAction(Field field, string action) => new(field.Id, action);

    /// <summary>An app or a folder added by what was typed or picked.</summary>
    public static SettingsActionRequest? Add(Field field, string value) =>
        string.IsNullOrWhiteSpace(value) || !field.Actions.Contains("add") ? null
            : new SettingsActionRequest(field.Id, "add", value: JsonValue.Create(value.Trim()));

    /// <summary>The field's actions that a list shows as its own buttons (add has its own box; save is the form's).</summary>
    public static IReadOnlyList<string> ListActions(Field field) => field.Actions.Where(a => a is not "add").ToList();

    // MARK: Forms (a custom command's editor)

    /// <summary>What the form shows first: an item's value's keys, or each form field's own value (a new one).</summary>
    public static Dictionary<string, JsonNode?> FormValues(Field field, Item? item)
    {
        var values = new Dictionary<string, JsonNode?>();
        var definition = item?.Value as JsonObject;
        foreach (var form in field.Form)
        {
            if (definition is null)
            {
                values[form.Id] = form.Kind == "words" ? JsonValue.Create(form.Text ?? "") : form.Value?.DeepClone();
                continue;
            }
            var value = definition[form.Id];
            values[form.Id] = form.Kind == "words" && value is JsonArray words
                ? JsonValue.Create(CommandLine(words.Select(w => (string?)w ?? "")))
                : value?.DeepClone();
        }
        return values;
    }

    /// <summary>Whether a form's field shows with the form's values as they are (its <c>when</c>).</summary>
    public static bool IsShown(Field form, IReadOnlyDictionary<string, JsonNode?> values) =>
        form.When.All(rule => rule.Value.Any(v => JsonNode.DeepEquals(v, values.GetValueOrDefault(rule.Key))));

    /// <summary>The form saved: the item's value (or a new one) with the shown fields' values; a text left empty, and a
    /// field not shown, left out.</summary>
    public static SettingsActionRequest SaveForm(Field field, Item? item, IReadOnlyDictionary<string, JsonNode?> values)
    {
        var definition = (item?.Value as JsonObject)?.DeepClone() as JsonObject ?? [];
        foreach (var form in field.Form)
        {
            definition.Remove(form.Id);
            if (!IsShown(form, values)) continue;
            var value = values.GetValueOrDefault(form.Id);
            if (value is null || (value is JsonValue v && v.TryGetValue<string>(out var text) && text.Trim().Length == 0)) continue;
            definition[form.Id] = value.DeepClone();
        }
        return new SettingsActionRequest(field.Id, "save", item: item?.Id, value: definition);
    }

    /// <summary>A program and its arguments as one line, quoted where needed: the core's <c>CustomCommand.commandLine</c>,
    /// which the engine splits back.</summary>
    public static string CommandLine(IEnumerable<string> argv) =>
        string.Join(" ", argv.Select(a => a.Length == 0 || a.Any(c => c is ' ' or '\t' or '"' or '\'' or '\\')
            ? "\"" + a.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"" : a));
}
