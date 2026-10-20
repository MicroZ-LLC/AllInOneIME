using System.Text.Json;
using System.Text.Json.Nodes;

namespace AllInOneIME.Settings.Document;

/// <summary>
/// The settings as the engine sends them (§12.3): sections of fields, with their text in the interface language and
/// only those that apply now on Windows. The window knows no setting: it draws what this says. What a field leaves out
/// is null here (no <c>value</c> means null: a text not set, "follow the system").
/// </summary>
public sealed class SettingsDocument
{
    public required string Language { get; init; }
    public required string Platform { get; init; }
    /// <summary>The config file can't be read: every field is read-only until it is fixed.</summary>
    public string? LoadError { get; init; }
    public string? SaveError { get; init; }
    public required IReadOnlyList<Section> Sections { get; init; }
    /// <summary>The words of the window's own controls, by name (<c>action.setKey</c>, <c>moveUp</c> …).</summary>
    public required IReadOnlyDictionary<string, string> Strings { get; init; }
    /// <summary>The document as it came, for comparing one field with its next version.</summary>
    public required JsonObject Json { get; init; }

    public static SettingsDocument Parse(JsonObject json) => new()
    {
        Language = Text(json["language"]) ?? "en",
        Platform = Text(json["platform"]) ?? "windows",
        LoadError = Text(json["loadError"]),
        SaveError = Text(json["saveError"]),
        Sections = Array(json["sections"]).Select(Section.Parse).ToList(),
        Strings = (json["strings"] as JsonObject)?.Where(p => Text(p.Value) is not null)
            .ToDictionary(p => p.Key, p => Text(p.Value)!) ?? new Dictionary<string, string>(),
        Json = json,
    };

    /// <summary>The field <paramref name="id"/>, wherever it is: in a section, or one of an item's own fields.</summary>
    public Field? Find(string id) => Sections.Select(s => Field.Find(id, s.Fields)).FirstOrDefault(f => f is not null);

    internal static IEnumerable<JsonObject> Array(JsonNode? node) => (node as JsonArray)?.OfType<JsonObject>() ?? [];

    internal static IReadOnlyList<string> StringList(JsonNode? node) =>
        (node as JsonArray)?.Select(Text).OfType<string>().ToList() ?? [];

    /// <summary>A string, or null for anything else (a later engine's number where a string was): what is drawn never
    /// throws on a value of another type.</summary>
    public static string? Text(JsonNode? node) => node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public static double? Number(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() == JsonValueKind.Number ? value.GetValue<double>() : null;

    public static bool? Bool(JsonNode? node) =>
        node is JsonValue value && value.GetValueKind() is JsonValueKind.True or JsonValueKind.False ? value.GetValue<bool>() : null;
}

/// <summary>A page of settings: General, Input, AI Provider …</summary>
public sealed class Section
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public string? Footer { get; init; }
    public required IReadOnlyList<Field> Fields { get; init; }

    public static Section Parse(JsonObject json) => new()
    {
        Id = SettingsDocument.Text(json["id"]) ?? "",
        Title = SettingsDocument.Text(json["title"]) ?? "",
        Footer = SettingsDocument.Text(json["footer"]),
        Fields = SettingsDocument.Array(json["fields"]).Select(Field.Parse).ToList(),
    };
}

/// <summary>One setting, or a list, an action, a note (§12.3: its <c>kind</c> says which).</summary>
public sealed class Field
{
    public required string Id { get; init; }
    /// <summary><c>toggle</c>, <c>integer</c>, <c>number</c>, <c>text</c>, <c>choice</c>, <c>choices</c>, <c>words</c>,
    /// <c>secret</c>, <c>items</c>, <c>info</c>, <c>button</c>; a later engine may send others.</summary>
    public required string Kind { get; init; }
    public required string Label { get; init; }
    public string? Help { get; init; }
    public JsonNode? Value { get; init; }
    public string? Placeholder { get; init; }
    public IReadOnlyList<Choice> Choices { get; init; } = [];
    public bool Ordered { get; init; }
    public int? MinCount { get; init; }
    public int? MaxCount { get; init; }
    public double? Min { get; init; }
    public double? Max { get; init; }
    public double? Step { get; init; }
    public bool Optional { get; init; }
    public bool ReadOnly { get; init; }
    public string? Status { get; init; }
    public bool? IsSet { get; init; }
    public IReadOnlyList<string> Actions { get; init; } = [];
    public IReadOnlyList<Item> Items { get; init; } = [];
    /// <summary>An action that takes a while runs on it now (a test, the library's download): <c>cancel</c> is among
    /// its actions (§12.5).</summary>
    public bool Running { get; init; }
    /// <summary>A <c>words</c> field's list as the one line it shows (and takes).</summary>
    public string? Text { get; init; }
    /// <summary><c>folder</c> or <c>file</c>: the system's open panel fills it in; on an <c>items</c> field, the path its
    /// <c>add</c> takes.</summary>
    public string? Picker { get; init; }
    public bool Multiline { get; init; }
    /// <summary>The actions that take a text the user types, sent as the action's <c>value</c> (a link to test, the app
    /// or folder to add; the box's hint is the <c>placeholder</c>).</summary>
    public IReadOnlyList<string> TextActions { get; init; } = [];
    /// <summary>What an items field's items' <c>value</c> is (a custom command's definition): a field for each of its
    /// keys, the editor's.</summary>
    public IReadOnlyList<Field> Schema { get; init; } = [];
    /// <summary>A schema's field that applies only while the definition's other field has one of these values.</summary>
    public IReadOnlyDictionary<string, IReadOnlyList<JsonNode?>> When { get; init; } = new Dictionary<string, IReadOnlyList<JsonNode?>>();
    /// <summary>The field as it came: two versions of it are the same field drawn the same way when they are equal.</summary>
    public required JsonObject Json { get; init; }

    public static Field Parse(JsonObject json) => new()
    {
        Id = SettingsDocument.Text(json["id"]) ?? "",
        Kind = SettingsDocument.Text(json["kind"]) ?? "",
        Label = SettingsDocument.Text(json["label"]) ?? "",
        Help = SettingsDocument.Text(json["help"]),
        Value = json["value"],
        Placeholder = SettingsDocument.Text(json["placeholder"]),
        Choices = SettingsDocument.Array(json["choices"]).Select(Choice.Parse).ToList(),
        Ordered = SettingsDocument.Bool(json["ordered"]) == true,
        MinCount = (int?)SettingsDocument.Number(json["minCount"]),
        MaxCount = (int?)SettingsDocument.Number(json["maxCount"]),
        Min = SettingsDocument.Number(json["min"]),
        Max = SettingsDocument.Number(json["max"]),
        Step = SettingsDocument.Number(json["step"]),
        Optional = SettingsDocument.Bool(json["optional"]) == true,
        ReadOnly = SettingsDocument.Bool(json["readOnly"]) == true,
        Status = SettingsDocument.Text(json["status"]),
        IsSet = SettingsDocument.Bool(json["isSet"]),
        Actions = SettingsDocument.StringList(json["actions"]),
        Items = SettingsDocument.Array(json["items"]).Select(Item.Parse).ToList(),
        Running = SettingsDocument.Bool(json["running"]) == true,
        Text = SettingsDocument.Text(json["text"]),
        Picker = SettingsDocument.Text(json["picker"]),
        Multiline = SettingsDocument.Bool(json["multiline"]) == true,
        TextActions = SettingsDocument.StringList(json["textActions"]),
        Schema = SettingsDocument.Array(json["schema"]).Select(Parse).ToList(),
        When = (json["when"] as JsonObject)?.ToDictionary(p => p.Key, p => (IReadOnlyList<JsonNode?>)((p.Value as JsonArray)?.ToList() ?? []))
            ?? new Dictionary<string, IReadOnlyList<JsonNode?>>(),
        Json = json,
    };

    internal static Field? Find(string id, IEnumerable<Field> fields)
    {
        foreach (var field in fields)
        {
            if (field.Id == id) return field;
            foreach (var item in field.Items)
            {
                if (Find(id, item.Fields) is { } found) return found;
            }
        }
        return null;
    }

    /// <summary>The value as a string, when it is one.</summary>
    public string? StringValue => SettingsDocument.Text(Value);

    /// <summary>The value as an array of strings (a <c>choices</c> or <c>words</c> field's).</summary>
    public IReadOnlyList<string> StringsValue => SettingsDocument.StringList(Value);

    public double? NumberValue => SettingsDocument.Number(Value);

    public bool? BoolValue => SettingsDocument.Bool(Value);
}

/// <summary>A choice: the value set, and how it reads.</summary>
public sealed class Choice
{
    public JsonNode? Value { get; init; }
    public required string Label { get; init; }
    public string? Note { get; init; }
    /// <summary>Shown (it is the value now) but not to be picked: another platform's, or not available.</summary>
    public bool Disabled { get; init; }

    public static Choice Parse(JsonObject json) => new()
    {
        Value = json["value"],
        Label = SettingsDocument.Text(json["label"]) ?? "",
        Note = SettingsDocument.Text(json["note"]),
        Disabled = SettingsDocument.Bool(json["disabled"]) == true,
    };

    /// <summary>Whether this choice's value is <paramref name="value"/> (null and a missing value are the same).</summary>
    public bool Is(JsonNode? value) => JsonNode.DeepEquals(Value, value);
}

/// <summary>One thing of an <c>items</c> field: a plugin, an app, a folder, an extension, a custom command.</summary>
public sealed class Item
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public string? Detail { get; init; }
    /// <summary>Its definition, as the field's <c>schema</c> describes it.</summary>
    public JsonNode? Value { get; init; }
    public IReadOnlyList<string> Actions { get; init; } = [];
    /// <summary>An action that takes a while runs on it now (an install): <c>cancel</c> is among its actions.</summary>
    public bool Running { get; init; }
    /// <summary>Its own settings.</summary>
    public IReadOnlyList<Field> Fields { get; init; } = [];

    public static Item Parse(JsonObject json) => new()
    {
        Id = SettingsDocument.Text(json["id"]) ?? "",
        Title = SettingsDocument.Text(json["title"]) ?? "",
        Detail = SettingsDocument.Text(json["detail"]),
        Value = json["value"],
        Actions = SettingsDocument.StringList(json["actions"]),
        Running = SettingsDocument.Bool(json["running"]) == true,
        Fields = SettingsDocument.Array(json["fields"]).Select(Field.Parse).ToList(),
    };
}
