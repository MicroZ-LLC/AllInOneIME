using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Presentation;
using AllInOneIME.Settings.Wire;
using Xunit;

namespace AllInOneIME.Settings.Tests;

/// <summary>
/// The documents the engine really sends (Documents/: the golden's, every kind of field in four languages, Notion, a
/// broken file), drawn by kind: every field gets a control and a name, and each thing the user does makes the request
/// the protocol wants (§12.3, §12.4, §12.5).
/// </summary>
public class RendererTests
{
    public static TheoryData<string> Documents => new(Fixtures.DocumentNames);

    static IEnumerable<Field> AllFields(SettingsDocument document)
    {
        IEnumerable<Field> Walk(IEnumerable<Field> fields) =>
            fields.SelectMany(f => new[] { f }.Concat(Walk(f.Items.SelectMany(i => i.Fields))).Concat(Walk(f.Form)));
        return Walk(document.Sections.SelectMany(s => s.Fields));
    }

    [Theory]
    [MemberData(nameof(Documents))]
    public void EveryFieldIsDrawnAndNamed(string name)
    {
        var document = Fixtures.Document(name);
        Assert.Equal("windows", document.Platform);
        Assert.NotEmpty(document.Sections);
        Assert.All(document.Sections, s => Assert.False(string.IsNullOrWhiteSpace(s.Title)));
        Assert.Equal(document.Sections.Count, document.Sections.Select(s => s.Id).Distinct().Count());
        var ids = new HashSet<string>();
        foreach (var field in AllFields(document))
        {
            Assert.NotEqual(FieldControl.Unknown, FieldPresenter.ControlFor(field));
            Assert.False(string.IsNullOrWhiteSpace(field.Label), $"{field.Id} has no label (its accessible name)");
            if (!field.Id.Contains('/') && field.Form.Count == 0) Assert.True(ids.Add(field.Id) || IsFormField(document, field.Id), $"{field.Id} twice");
            // Its actions have words in the window's own (the document's, or the window's English).
            foreach (var action in field.Actions.Concat(field.Items.SelectMany(i => i.Actions)))
            {
                Assert.False(new WindowText(document).Action(action).StartsWith("action.", StringComparison.Ordinal), action);
            }
            // What's picked is one of its choices.
            if (field.Kind == "choice" && field.Value is not null) Assert.True(FieldPresenter.SelectedChoice(field) >= 0, field.Id);
        }
    }

    static bool IsFormField(SettingsDocument document, string id) =>
        AllFields(document).Any(f => f.Form.Any(form => form.Id == id));

    [Theory]
    [MemberData(nameof(Documents))]
    public void TheWindowsWordsAreTheDocuments(string name)
    {
        var document = Fixtures.Document(name);
        var text = new WindowText(document);
        Assert.False(string.IsNullOrWhiteSpace(text["window.title"]));
        Assert.Equal(document.Strings["save"], text["save"]);
        Assert.Contains("“x”", new WindowText(null).Confirmation("delete", false, "x"));
    }

    /// <summary>Every kind the core has is in the documents, and each has its control.</summary>
    [Fact]
    public void EveryKindIsThere()
    {
        var kinds = Fixtures.DocumentNames.SelectMany(n => AllFields(Fixtures.Document(n))).Select(f => f.Kind).ToHashSet();
        foreach (var kind in new[] { "toggle", "integer", "number", "text", "choice", "choices", "words", "secret", "items", "info", "button" })
        {
            Assert.Contains(kind, kinds);
        }
        var controls = Fixtures.DocumentNames.SelectMany(n => AllFields(Fixtures.Document(n))).Select(FieldPresenter.ControlFor).ToHashSet();
        Assert.Equal(Enum.GetValues<FieldControl>().Except([FieldControl.Unknown]).Order(), controls.Order());
    }

    [Theory]
    [InlineData("every-kind-en", "General", "Typing speed")]
    [InlineData("every-kind-zh-Hans", "通用", "打字速度")]
    [InlineData("every-kind-fr", "Général", null)]
    [InlineData("every-kind-ja", null, null)]
    public void TheDocumentIsInTheInterfaceLanguage(string name, string? general, string? speed)
    {
        var document = Fixtures.Document(name);
        Assert.Equal(name["every-kind-".Length..], document.Language);
        var english = Fixtures.Document("every-kind-en");
        if (general is not null) Assert.Equal(general, document.Sections[0].Title);
        if (speed is not null) Assert.Equal(speed, document.Find("typeOutRate")!.Label);
        if (name != "every-kind-en")
        {
            // Translated: the sections' titles and the window's words aren't the English ones.
            Assert.NotEqual(english.Sections[1].Title, document.Sections[1].Title);
            Assert.NotEqual(english.Strings["moveUp"], document.Strings["moveUp"]);
        }
    }

    [Fact]
    public void ABrokenFileIsShownReadOnly()
    {
        var document = Fixtures.Document("broken-en");
        Assert.NotNull(document.LoadError);
        var changeable = AllFields(document).Where(f => f.Kind is "toggle" or "integer" or "number" or "text" or "choice" or "choices" or "words");
        Assert.All(changeable, f => Assert.False(FieldPresenter.IsEnabled(f, document), f.Id));
    }

    [Fact]
    public void TheItemsOwnFieldsAreFound()
    {
        var document = Fixtures.Document("every-kind-en");
        var apps = document.Find("apps.profiles")!;
        Assert.Equal("win:notepad.exe", apps.Items.Single().Id);
        Assert.Equal(FieldControl.Toggle, FieldPresenter.ControlFor(document.Find("apps.win:notepad.exe.noAI")!));
        Assert.Equal(FieldControl.Secret, FieldPresenter.ControlFor(document.Find("extensions.preference.tools.apiToken")!));
        Assert.Equal(FieldControl.ComboBox, FieldPresenter.ControlFor(document.Find("extensions.preference.tools.region")!));
    }

    // MARK: What each thing the user does sends

    [Fact]
    public void ASwitch()
    {
        var typeOut = Fixtures.Document("every-kind-en").Find("typeOut")!;
        Assert.Null(FieldPresenter.Toggled(typeOut, true));
        var off = FieldPresenter.Toggled(typeOut, false)!;
        Assert.Equal("typeOut", off.Field);
        Assert.False(off.Value!.GetValue<bool>());
    }

    [Fact]
    public void AChoiceWhoseValueIsNull()
    {
        var language = Fixtures.Document("every-kind-en").Find("uiLanguage")!;
        Assert.Equal(FieldControl.ComboBox, FieldPresenter.ControlFor(language));
        var follow = language.Choices.ToList().FindIndex(c => c.Value is null);
        Assert.Equal(0, follow);
        var request = FieldPresenter.Picked(language, follow)!;
        Assert.Null(request.Value);
        Assert.Null(FieldPresenter.Picked(language, FieldPresenter.SelectedChoice(language)));
        var french = language.Choices.ToList().FindIndex(c => (string?)c.Value == "fr");
        Assert.Equal("fr", (string?)FieldPresenter.Picked(language, french)!.Value);
    }

    [Fact]
    public void ADisabledChoiceIsNotPicked()
    {
        var destination = Fixtures.Document("notion-en").Find("notes.destination")!;
        Assert.DoesNotContain(destination.Choices, c => c.Disabled && FieldPresenter.Picked(destination, destination.Choices.ToList().IndexOf(c)) is not null);
    }

    [Fact]
    public void Numbers()
    {
        var document = Fixtures.Document("every-kind-en");
        var tokens = document.Find("maxTokens")!;
        Assert.Equal(FieldControl.NumberBox, FieldPresenter.ControlFor(tokens));
        Assert.Equal(1500, FieldPresenter.Integer(tokens, 1499.6)!.Value!.GetValue<double>());
        Assert.Null(FieldPresenter.Integer(tokens, tokens.NumberValue!.Value));
        var rate = document.Find("typeOutRate")!;
        Assert.Equal(FieldControl.Slider, FieldPresenter.ControlFor(rate));
        Assert.NotNull(rate.Status);
        var temperature = document.Find("temperature")!;
        Assert.Equal(FieldControl.OptionalSlider, FieldPresenter.ControlFor(temperature));
        Assert.Null(FieldPresenter.OptionalNumber(temperature, false, 0.5)!.Value);
        Assert.Equal(0.7, FieldPresenter.OptionalNumber(temperature, true, 0.68)!.Value!.GetValue<double>(), 6);
    }

    [Fact]
    public void ATextCommitted()
    {
        var document = Fixtures.Document("every-kind-en");
        var region = document.Find("bedrock.region")!;
        Assert.True(region.Optional);
        Assert.Null(FieldPresenter.Text(region, region.StringValue ?? ""));
        Assert.Equal("eu-west-1", (string?)FieldPresenter.Text(region, "eu-west-1")!.Value);
        var model = document.Find("bedrock.modelId")!;
        Assert.Equal(FieldControl.TextWithSuggestions, FieldPresenter.ControlFor(model));
        Assert.True(FieldPresenter.IsWide(model));
        Assert.Equal("folder", document.Find("notes.folder")!.Pick);
    }

    [Fact]
    public void AWordsLine()
    {
        var document = Fixtures.Document("every-kind-en");
        var words = document.Find("redaction.customWords")!;
        Assert.Equal("Project X, Jane", FieldPresenter.WordsLine(words));
        Assert.Null(FieldPresenter.Words(words, "Project X, Jane"));
        Assert.Equal("Project X, Jane, Doe", (string?)FieldPresenter.Words(words, "Project X, Jane, Doe")!.Value);
        var agent = document.Find("agentCommand")!;
        Assert.Equal("muse --model \"big one\"", FieldPresenter.WordsLine(agent));
        // An engine without `text`: the words, split at commas.
        var old = Field.Parse(new JsonObject { ["id"] = "w", ["kind"] = "words", ["label"] = "W", ["value"] = new JsonArray("a") });
        Assert.Equal(["a", "b c"], ((JsonArray)FieldPresenter.Words(old, "a, b c")!.Value!).Select(v => (string?)v));
    }

    [Fact]
    public void ACheckList()
    {
        var fuzzy = Fixtures.Document("every-kind-en").Find("fuzzyPinyin")!;
        Assert.Equal(FieldControl.CheckList, FieldPresenter.ControlFor(fuzzy));
        var ids = fuzzy.Choices.Select(c => (string?)c.Value).ToList();
        Assert.True(FieldPresenter.IsPicked(fuzzy, ids.IndexOf("z-zh")));
        var on = FieldPresenter.Checked(fuzzy, ids.IndexOf("c-ch"), true)!;
        // In the choices' order.
        Assert.Equal(ids.Where(i => i is "z-zh" or "c-ch" or "en-eng"), ((JsonArray)on.Value!).Select(v => (string?)v));
        Assert.Null(FieldPresenter.Checked(fuzzy, ids.IndexOf("z-zh"), true));
    }

    [Fact]
    public void AnOrderedList()
    {
        var languages = Fixtures.Document("every-kind-en").Find("inputLanguages")!;
        Assert.Equal(FieldControl.OrderedList, FieldPresenter.ControlFor(languages));
        Assert.Equal(["en", "zh"], FieldPresenter.PickedValues(languages).Select(v => (string?)v));
        Assert.Equal(["zh", "en"], ((JsonArray)FieldPresenter.Moved(languages, 1, -1)!.Value!).Select(v => (string?)v));
        Assert.Null(FieldPresenter.Moved(languages, 0, -1));
        Assert.Equal(["zh"], ((JsonArray)FieldPresenter.Removed(languages, 0)!.Value!).Select(v => (string?)v));
        var french = FieldPresenter.Addable(languages).Single(c => (string?)c.Value == "fr");
        Assert.Equal(["en", "zh", "fr"], ((JsonArray)FieldPresenter.Added(languages, french)!.Value!).Select(v => (string?)v));
        Assert.Equal("English", FieldPresenter.LabelOf(languages, JsonValue.Create("en")));
    }

    [Fact]
    public void ASecret()
    {
        var token = Fixtures.Document("every-kind-en").Find("extensions.preference.tools.apiToken")!;
        Assert.Equal(false, token.IsSet);
        Assert.Null(token.Value);
        Assert.Null(FieldPresenter.SaveSecret(token, "  "));
        var save = FieldPresenter.SaveSecret(token, "tok-123")!;
        Assert.Equal(("setKey", "tok-123"), (save.Action, save.Key));
        Assert.Null(FieldPresenter.RemoveSecret(token));
        var key = Fixtures.Document("golden-06-settingsAction-anthropic_key-setKey").Find("anthropic.key")!;
        Assert.Equal(true, key.IsSet);
        Assert.EndsWith("a1b2", key.Status);
        Assert.Equal("removeKey", FieldPresenter.RemoveSecret(key)!.Action);
    }

    [Fact]
    public void ButtonsAndTheirValue()
    {
        var document = Fixtures.Document("notion-en");
        var link = document.Find("notes.notion")!;
        Assert.Equal(FieldControl.Button, FieldPresenter.ControlFor(link));
        Assert.True(FieldPresenter.IsWide(link));
        var run = FieldPresenter.Run(link, " https://www.notion.so/page ")!;
        Assert.Equal(("test", "https://www.notion.so/page"), (run.Action, (string?)run.Value));
        Assert.True(run.TakesAWhile);
        Assert.Null(FieldPresenter.Run(link, "")!.Value);
        var test = Fixtures.Document("golden-01-settingsGet").Find("provider.test")!;
        Assert.False(FieldPresenter.IsWide(test));
    }

    [Fact]
    public void ListsAddAndAct()
    {
        var document = Fixtures.Document("every-kind-en");
        var apps = document.Find("apps.profiles")!;
        Assert.Equal("notepad.exe", (string?)FieldPresenter.Add(apps, " notepad.exe ")!.Value);
        Assert.Null(FieldPresenter.Add(apps, ""));
        var folders = document.Find("extensions.folders")!;
        Assert.Equal("folder", folders.Pick);
        var remove = FieldPresenter.ItemAction(folders, folders.Items[0], "remove");
        Assert.Equal((folders.Id, "remove", folders.Items[0].Id), (remove.Field, remove.Action, remove.Item));
        Assert.Empty(FieldPresenter.ListActions(apps));
        Assert.Equal(["browse"], FieldPresenter.ListActions(document.Find("plugins.library")!));
    }

    /// <summary>The custom command editor: filled in from a command (its command line as one line), the fields of its
    /// type only, saved with what the form doesn't show kept.</summary>
    [Fact]
    public void TheCommandForm()
    {
        var commands = Fixtures.Document("every-kind-en").Find("commands.custom")!;
        var upper = commands.Items.Single(i => i.Id == "upper");
        var values = FieldPresenter.FormValues(commands, upper);
        Assert.Equal("run", (string?)values["type"]);
        Assert.Equal("python3 -c print(input().upper())", (string?)values["argv"]);
        Assert.True(FieldPresenter.IsShown(commands.Form.Single(f => f.Id == "argv"), values));
        Assert.False(FieldPresenter.IsShown(commands.Form.Single(f => f.Id == "prompt"), values));
        values["argv"] = JsonValue.Create("python3 up.py");
        values["prompt"] = JsonValue.Create("not shown");
        var save = FieldPresenter.SaveForm(commands, upper, values);
        var definition = (JsonObject)save.Value!;
        Assert.Equal(("save", "upper"), (save.Action, save.Item));
        Assert.Equal("python3 up.py", (string?)definition["argv"]);
        Assert.False(definition.ContainsKey("prompt"));
        Assert.False(definition.ContainsKey("summary"));

        var fresh = FieldPresenter.FormValues(commands, null);
        Assert.Equal("prompt", (string?)fresh["type"]);
        fresh["name"] = JsonValue.Create("polite");
        fresh["prompt"] = JsonValue.Create("Be polite");
        var created = FieldPresenter.SaveForm(commands, null, fresh);
        Assert.Null(created.Item);
        Assert.Equal(["name", "prompt", "type"], ((JsonObject)created.Value!).Select(p => p.Key).Order());
    }

    /// <summary>The command line as the core writes it for Windows (CustomCommand.commandLine, its Windows rules), so
    /// that it splits back the same: a path's backslashes as they are.</summary>
    [Theory]
    [InlineData(new[] { "python3", "-c", "{input}" }, "python3 -c {input}")]
    [InlineData(new[] { "say", "hello world" }, "say \"hello world\"")]
    [InlineData(new[] { @"C:\Tools\run.exe", @"C:\dir\", "{input}" }, @"C:\Tools\run.exe C:\dir\ {input}")]
    [InlineData(new[] { @"C:\Program Files\x.exe", "x\"y", "", @"C:\My Files\" }, @"""C:\Program Files\x.exe"" ""x\""y"" """" ""C:\My Files\\""")]
    public void CommandLines(string[] argv, string line) => Assert.Equal(line, FieldPresenter.CommandLine(argv));

    /// <summary>A command's arguments as one line, read back by Windows (CommandLineToArgvW, whose rules the engine
    /// splits the line with): the same arguments.</summary>
    [Theory]
    [MemberData(nameof(ArgumentLists))]
    public void CommandLinesSplitBackOnWindows(string[] argv)
    {
        var line = FieldPresenter.CommandLine(argv);
        var read = CommandLineToArgvW(line, out var count);
        try
        {
            var back = Enumerable.Range(0, count).Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(read, i * IntPtr.Size))).ToArray();
            Assert.Equal(argv, back);
        }
        finally
        {
            LocalFree(read);
        }
    }

    public static TheoryData<string[]> ArgumentLists => new(
        [@"C:\Tools\run.exe", "{input}", @"\\server\share\a b"],
        [@"C:\Program Files\Tool\t.exe", @"say ""hi"" \ there", @"C:\dir\", "", "tab\there"],
        ["py", @"\\", @"\", @"a\\""b", @"x\y\", @"C:\My Files\"]);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CommandLineToArgvW(string commandLine, out int count);

    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr memory);

    [Theory]
    [InlineData("zh-CN", "zh-Hans")]
    [InlineData("zh-TW", "zh-Hant")]
    [InlineData("zh-Hant-HK", "zh-Hant")]
    [InlineData("pt-PT", "pt-BR")]
    [InlineData("fr-CA", "fr")]
    [InlineData("ja-JP", "ja")]
    [InlineData("it-IT", "en")]
    public void TheWindowsOwnWordsFollowWindows(string culture, string language)
    {
        Assert.Equal(language, WindowText.Language(new CultureInfo(culture)));
        Assert.False(string.IsNullOrWhiteSpace(WindowText.Own(OwnText.CouldNotStart, language)));
    }

    [Fact]
    public void Options()
    {
        var options = AppOptions.Parse(["--pipe", "aio-test", "--engine", @"C:\e.exe", "--engine-args", "--test --config c.json",
                                         "--theme", "dark", "--screenshots", "out", "--size", "800x600", "--unknown"]);
        Assert.Equal(("aio-test", @"C:\e.exe", "--test --config c.json", "dark", "out", (800, 600)),
                     (options.Pipe, options.Engine, options.EngineArguments, options.Theme, options.Screenshots, options.Size!.Value));
        Assert.Throws<ArgumentException>(() => AppOptions.Parse(["--theme", "blue"]));
        Assert.Null(AppOptions.Parse([]).Pipe);
    }

    [Fact]
    public void PipeNamesAsTheEngineMakesThem()
    {
        Assert.StartsWith(@"\\.\pipe\AllInOneIME-S-1-", PipeNames.UserPipe);
        Assert.EndsWith("-v1", PipeNames.UserPipe);
        Assert.Equal(@"\\.\pipe\aio-test", PipeNames.Full("aio-test"));
        Assert.Equal("aio-test", PipeNames.ShortName(@"\\.\pipe\aio-test"));
        var user = PipeNames.EngineMutex(PipeNames.UserPipe);
        Assert.StartsWith(@"Local\AllInOneIME-Engine-S-1-", user);
        Assert.Equal(user + "-aio-test_1", PipeNames.EngineMutex("aio-test.1"));
    }
}
