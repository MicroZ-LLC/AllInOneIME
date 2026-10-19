using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using AllInOneIME.Settings.Wire;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.UIA3;

namespace AllInOneIME.Settings.UITests;

/// <summary>
/// The Settings app end to end, as a user would use it, through UI Automation's patterns only (no key is pressed, no
/// other window is touched), against a test engine of its own:
///
/// 1. a stand-in AI provider on localhost (Windows/Scripts/stub-provider.py), which wants a fake key;
/// 2. a config in a temporary folder; the Settings app started on a pipe of its own, with the engine to start there (a
///    build's, in test mode, its keys in memory): the app finds nothing on the pipe and starts it, as it starts the
///    installed engine from the registry;
/// 3. every section shown, each control named for Narrator and reachable from the keyboard (and captured when the
///    window happens to be in front);
/// 4. a switch, a choice, an ordered list, a check box and a text changed, a key saved (and the box cleared), Test
///    Connection run against the stand-in;
///    config.json, the engine's key store (through the wire: saved, its last 4) and the stand-in's log checked;
/// 5. changes from elsewhere shown: config.json edited by hand, another window's change, the interface language;
/// 6. the window closed; the app's own screenshots of every section, light and dark.
///
///     AllInOneIMESettings.UITests --app EXE --engine EXE --stub stub-provider.py --python PYTHON --out DIR
/// </summary>
static class Program
{
    static int failures;
    static StreamWriter log = StreamWriter.Null;

    static int Main(string[] args)
    {
        SetProcessDpiAwarenessContext(-4);  // per monitor v2: the window's rectangle in real pixels
        var options = Options.Parse(args);
        Directory.CreateDirectory(options.Out);
        log = new StreamWriter(Path.Combine(options.Out, "e2e-report.txt")) { AutoFlush = true };
        var work = Directory.CreateTempSubdirectory("aio-settings-e2e-");
        Process? stub = null, app = null;
        uint enginePid = 0;
        try
        {
            // The fake key the window will save, and the only one the stand-in takes.
            var key = "sk-e2e-" + Guid.NewGuid().ToString("N")[..16] + "z9y8";
            stub = StartStub(options, work.FullName, key, out var port, out var stubLog);
            var config = Path.Combine(work.FullName, "config.json");
            File.WriteAllText(config, new JsonObject
            {
                ["uiLanguage"] = "en", ["provider"] = "anthropic", ["anthropic"] = new JsonObject { ["baseURL"] = $"http://127.0.0.1:{port}" },
                ["inputLanguages"] = new JsonArray("en"), ["outputLanguages"] = new JsonArray("en"), ["outputLanguage"] = "en",
                ["rewriteStyles"] = new JsonArray(), ["typeOut"] = false, ["candidateLayout"] = "horizontal",
                ["extensionFolders"] = new JsonArray(),
            }.ToJsonString());
            var pipe = $"aio-settings-e2e-{Environment.ProcessId}";
            var engineArguments = $"--test --clock system --no-keychain --no-panel --config \"{config}\" --pipe {pipe}";
            app = Process.Start(new ProcessStartInfo(options.App)
            {
                ArgumentList = { "--pipe", pipe, "--engine", options.Engine, "--engine-args", engineArguments },
                UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,  // not this log's handles
            })!;
            Say($"app pid {app.Id}, pipe {pipe}, stub port {port}, folder {work.FullName}");
            using var automation = new UIA3Automation();
            var window = WaitFor("the window", () => FlaUI.Core.Application.Attach(app.Id).GetMainWindow(automation, TimeSpan.FromSeconds(1)), 60);
            var general = WaitFor("the sections (the engine started by the app, connected)", () => window.FindFirstDescendant(c => c.ByAutomationId("section:general")), 60);
            Check("the window's title is the document's", window.Title == "AllInOneIME Settings", window.Title);

            // Our own connection to the engine the app started: its pid, and its settings as the engine has them.
            using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(10));
            var transport = PipeTransport.ConnectAsync(pipe, TimeSpan.FromSeconds(10), cancellation.Token).GetAwaiter().GetResult();
            var client = SettingsClient.ConnectAsync(transport, "e2e", cancellation.Token).GetAwaiter().GetResult();
            enginePid = client.EnginePid;
            Check("the app started the engine (nothing served the pipe)", enginePid != 0 && Process.GetProcessById((int)enginePid).ProcessName == "AllInOneIMEEngine",
                  $"engine pid {enginePid}");

            // 3. Every section: shown, named, reachable, drawn.
            var shots = Path.Combine(options.Out, "e2e-shots");
            Directory.CreateDirectory(shots);
            var sections = window.FindAllDescendants(c => c.ByControlType(ControlType.ListItem)).Where(e => e.AutomationId.StartsWith("section:")).ToList();
            Check("13 sections in the pane", sections.Count >= 12, string.Join(", ", sections.Select(s => s.Name)));
            var index = 0;
            foreach (var section in sections)
            {
                var id = section.AutomationId["section:".Length..];
                Select(window, id);
                Thread.Sleep(600);
                var unnamed = Interactive(window).Where(e => string.IsNullOrWhiteSpace(e.Name)).Select(Describe).ToList();
                Check($"{id}: every control has a name", unnamed.Count == 0, string.Join("; ", unnamed));
                var unreachable = Interactive(window).Where(e => e.IsEnabled && !Reachable(e)).Select(Describe).ToList();
                Check($"{id}: every control is reachable from the keyboard", unreachable.Count == 0, string.Join("; ", unreachable));
                Capture(window, Path.Combine(shots, $"{++index:00}-{id}.png"));
            }

            // 4. A switch, a choice, a text.
            Select(window, "general");
            var typeOut = WaitFor("typeOut", () => window.FindFirstDescendant(c => c.ByAutomationId("typeOut")));
            Check("typeOut is a switch, off", typeOut.Patterns.Toggle.Pattern.ToggleState.Value == ToggleState.Off);
            typeOut.Patterns.Toggle.Pattern.Toggle();
            Check("typeOut saved in config.json", Eventually(() => Config(config)["typeOut"]?.GetValue<bool>() == true));
            Check("the typing speed appears (fields come and go)", Eventually(() => window.FindFirstDescendant(c => c.ByAutomationId("typeOutRate")) is not null));

            Select(window, "input");
            var layout = WaitFor("candidateLayout", () => window.FindFirstDescendant(c => c.ByAutomationId("candidateLayout"))).AsComboBox();
            layout.Select("Vertical");
            Check("candidateLayout saved in config.json", Eventually(() => (string?)Config(config)["candidateLayout"] == "vertical"),
                  (string?)Config(config)["candidateLayout"]);

            // An ordered list: Chinese added from its menu; then fuzzy pinyin, a check box each, appears and is checked.
            var add = WaitFor("inputLanguages' Add", () => window.FindFirstDescendant(c => c.ByAutomationId("inputLanguages/add")));
            add.Patterns.ExpandCollapse.Pattern.Expand();
            var chinese = WaitFor("Chinese in the menu", () => window.FindFirstDescendant(c => c.ByControlType(ControlType.MenuItem).And(c.ByName("Chinese (pinyin)"))));
            chinese.Patterns.Invoke.Pattern.Invoke();
            Check("Chinese added to the input languages, after English", Eventually(() =>
                string.Join(",", Config(config)["inputLanguages"]!.AsArray().Select(l => (string?)l)) == "en,zh"), Config(config)["inputLanguages"]?.ToJsonString());
            var pair = WaitFor("fuzzy pinyin z-zh", () => window.FindFirstDescendant(c => c.ByAutomationId("fuzzyPinyin/z-zh")));
            Check("fuzzy pinyin's boxes start cleared", pair.Patterns.Toggle.Pattern.ToggleState.Value == ToggleState.Off);
            pair.Patterns.Toggle.Pattern.Toggle();
            Check("fuzzy pinyin saved in config.json", Eventually(() =>
                string.Join(",", Config(config)["fuzzyPinyin"]?.AsArray().Select(l => (string?)l) ?? []) == "z-zh"));
            Check("its box shows checked", Eventually(() =>
                window.FindFirstDescendant(c => c.ByAutomationId("fuzzyPinyin/z-zh"))?.Patterns.Toggle.Pattern.ToggleState.Value == ToggleState.On));
            var moveUp = WaitFor("move Chinese up", () => window.FindFirstDescendant(c => c.ByAutomationId("inputLanguages/up/zh")));
            moveUp.AsButton().Invoke();
            Check("Chinese moved first (the default)", Eventually(() =>
                string.Join(",", Config(config)["inputLanguages"]!.AsArray().Select(l => (string?)l)) == "zh,en"));
            Capture(window, Path.Combine(shots, "input-changed.png"));

            Select(window, "provider");
            var model = WaitFor("anthropic.model", () => window.FindFirstDescendant(c => c.ByAutomationId("anthropic.model")));
            model.Patterns.Value.Pattern.SetValue("claude-e2e-model");
            window.FindFirstDescendant(c => c.ByAutomationId("anthropic.baseURL")).Focus();  // the focus leaves: committed
            Check("anthropic.model saved in config.json", Eventually(() => (string?)Config(config)["anthropic"]?["model"] == "claude-e2e-model"),
                  Config(config).ToJsonString());

            // A fake key: saved once, the box cleared, shown by its last 4, kept in the engine's memory, never in the file.
            var box = window.FindFirstDescendant(c => c.ByAutomationId("anthropic.key"));
            Check("the key's box is a password box", box.Properties.IsPassword.ValueOrDefault);
            box.Patterns.Value.Pattern.SetValue(key);
            window.FindFirstDescendant(c => c.ByAutomationId("anthropic.key/setKey")).AsButton().Invoke();
            Check("the window says the key is saved, by its last 4",
                  Eventually(() => window.FindFirstDescendant(c => c.ByName("✓ Saved · ends in z9y8")) is not null));
            Check("the key's box is empty again", Eventually(() => (box.Patterns.Value.PatternOrDefault?.Value.ValueOrDefault ?? "") == ""));
            var document = client.GetAsync(cancellation.Token).GetAwaiter().GetResult().Document;
            var keyField = document.Find("anthropic.key");
            Check("the engine has the key (its store in memory): set, ending in z9y8", keyField?.IsSet == true && keyField.Status?.EndsWith("z9y8") == true,
                  keyField?.Status);
            Check("the key isn't in config.json", !File.ReadAllText(config).Contains(key));

            var test = window.FindFirstDescendant(c => c.ByAutomationId("provider.test")).AsButton();
            test.Invoke();
            // Its outcome, under its label: "✓ 0.3 s: Hello there." (the key's state is a "✓" line too).
            var outcome = WaitFor("Test Connection's outcome", () => window.FindFirstDescendant(c => c.ByControlType(ControlType.Text)
                .And(new FlaUI.Core.Conditions.PropertyCondition(automation.PropertyLibrary.Element.Name, "Hello there.", PropertyConditionFlags.MatchSubstring))), 60);
            Check("Test Connection passed, with the stand-in's first version", outcome.Name.StartsWith("✓") && outcome.Name.Contains("Hello there."), outcome.Name);
            var requests = File.Exists(stubLog) ? File.ReadAllLines(stubLog).Select(l => JsonNode.Parse(l)!).ToList() : [];
            Check("the stand-in got one request, with the key the window saved",
                  requests.Count == 1 && (string?)requests[0]["kind"] == "anthropic" && requests[0]["keyOk"]?.GetValue<bool>() == true
                  && (string?)requests[0]["model"] == "claude-e2e-model", string.Join(" | ", requests.Select(r => r.ToJsonString())));
            Capture(window, Path.Combine(shots, "after-test-connection.png"));

            // 5. Changes made elsewhere: config.json by hand, another window, the interface language.
            var edited = Config(config);
            edited["maxTokens"] = 2500;
            File.WriteAllText(config, edited.ToJsonString());
            Select(window, "request");
            Check("a hand edit of config.json shows", Eventually(() => window.FindFirstDescendant(c => c.ByName("Up to 2500 output tokens")) is not null, 20));

            Select(window, "general");
            client.SetAsync("useSelection", JsonValue.Create(false), cancellation.Token).GetAwaiter().GetResult();
            Check("another window's change shows", Eventually(() =>
                window.FindFirstDescendant(c => c.ByAutomationId("useSelection"))?.Patterns.Toggle.Pattern.ToggleState.Value == ToggleState.Off));

            window.FindFirstDescendant(c => c.ByAutomationId("uiLanguage")).AsComboBox().Select("Français");
            Check("the interface language picked: the window in French", Eventually(() =>
                window.FindFirstDescendant(c => c.ByAutomationId("section:general"))?.Name == "Général", 20));
            Check("uiLanguage saved in config.json", (string?)Config(config)["uiLanguage"] == "fr");
            Capture(window, Path.Combine(shots, "french.png"));
            client.SetAsync("uiLanguage", JsonValue.Create("en"), cancellation.Token).GetAwaiter().GetResult();
            Check("and back in English", Eventually(() => window.FindFirstDescendant(c => c.ByAutomationId("section:general"))?.Name == "General", 20));

            // 6. Closed.
            client.DisposeAsync().AsTask().GetAwaiter().GetResult();
            window.Close();
            Check("the window closes", app.WaitForExit(15000));
        }
        catch (Exception error)
        {
            Check("no unexpected error", false, error.ToString());
        }
        finally
        {
            foreach (var process in new[] { app, stub })
            {
                try { if (process is { HasExited: false }) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            }
            Stop(enginePid);
        }

        // The app's own drawings of every section, light and dark, on an engine of their own.
        foreach (var theme in new[] { "light", "dark" }) Screenshots(options, work.FullName, theme);
        try { work.Delete(recursive: true); } catch (IOException) { }
        Say(failures == 0 ? "ALL PASSED" : $"{failures} FAILED");
        return failures == 0 ? 0 : 1;
    }

    // MARK: The parts

    static Process StartStub(Options options, string folder, string key, out int port, out string stubLog)
    {
        var portFile = Path.Combine(folder, "port");
        stubLog = Path.Combine(folder, "stub.log");
        var stub = Process.Start(new ProcessStartInfo(options.Python)
        {
            ArgumentList = { options.Stub, "--port", "0", "--port-file", portFile, "--log", stubLog, "--key", key, "--lifetime", "900",
                             "--versions", "Hello there.|Hi!|Greetings." },
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        })!;
        port = WaitFor("the stand-in's port", () => File.Exists(portFile) && int.TryParse(File.ReadAllText(portFile).Trim(), out var p) ? p : (int?)null, 20)!.Value;
        return stub;
    }

    static void Screenshots(Options options, string folder, string theme)
    {
        var config = Path.Combine(folder, $"every-{theme}.json");
        File.WriteAllText(config, EveryKind(folder).ToJsonString());
        var pipe = $"aio-settings-shots-{theme}-{Environment.ProcessId}";
        var output = Path.Combine(options.Out, "app-shots");
        var app = Process.Start(new ProcessStartInfo(options.App)
        {
            ArgumentList = { "--pipe", pipe, "--engine", options.Engine,
                             "--engine-args", $"--test --no-keychain --no-panel --config \"{config}\" --pipe {pipe}",
                             "--screenshots", output, "--theme", theme },
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
        })!;
        var done = app.WaitForExit(180000);
        Check($"the app drew every section ({theme})", done && File.Exists(Path.Combine(output, $"done-{theme}.txt")));
        if (!done) app.Kill();
        // Its engine: found by its pipe, stopped.
        try
        {
            var transport = PipeTransport.ConnectAsync(pipe, TimeSpan.FromSeconds(2), CancellationToken.None).GetAwaiter().GetResult();
            var client = SettingsClient.ConnectAsync(transport, "e2e", CancellationToken.None).GetAwaiter().GetResult();
            Stop(client.EnginePid);
        }
        catch (Exception)
        {
        }
    }

    /// <summary>A config that shows every kind of field: Bedrock, the typing speed, hidden words, a custom agent, an
    /// app's settings, a script extension bundle with each kind of preference, a custom command.</summary>
    static JsonObject EveryKind(string folder)
    {
        var extensions = Path.Combine(folder, "extensions");
        Directory.CreateDirectory(Path.Combine(extensions, "tools"));
        File.WriteAllText(Path.Combine(extensions, "tools", "extension.json"), """
            {"schemaVersion": 1, "name": "tools", "title": "Team Tools", "version": "1.2.0", "author": "Someone",
             "description": "Commands for the team",
             "preferences": [{"name": "apiToken", "type": "password", "title": "API token", "required": true},
                             {"name": "region", "type": "dropdown", "title": "Region", "default": "eu",
                              "data": [{"title": "Europe", "value": "eu"}, {"title": "Asia", "value": "asia"}]},
                             {"name": "verbose", "type": "checkbox", "title": "Verbose", "default": false},
                             {"name": "host", "title": "Host", "default": "example.com"}],
             "commands": [{"script": "find.sh", "name": "find", "title": "Find someone"}]}
            """);
        File.WriteAllText(Path.Combine(extensions, "tools", "find.sh"), "#!/bin/sh\necho found\n");
        File.WriteAllText(Path.Combine(extensions, "hello.sh"), "#!/bin/sh\n# @allinoneime.schemaVersion 1\n# @allinoneime.title Say hi\necho hi\n");
        return new JsonObject
        {
            ["uiLanguage"] = "en", ["provider"] = "bedrock", ["temperature"] = 0.5, ["inputLanguages"] = new JsonArray("en", "zh"),
            ["fuzzyPinyin"] = new JsonArray("z-zh"), ["typeOut"] = true,
            ["redaction"] = new JsonObject { ["enabled"] = true, ["customWords"] = new JsonArray("Project X") },
            ["agent"] = "custom", ["agentCommand"] = new JsonArray("muse", "--"),
            ["notes"] = new JsonObject { ["destination"] = "notion" },
            ["customCommands"] = new JsonArray(new JsonObject { ["name"] = "polite", ["type"] = "prompt", ["prompt"] = "Make it polite" }),
            ["appProfiles"] = new JsonObject { ["win:notepad.exe"] = new JsonObject { ["noAI"] = true, ["inputLanguage"] = "zh" } },
            ["extensionFolders"] = new JsonArray(extensions),
        };
    }

    static void Select(Window window, string section)
    {
        var item = WaitFor($"section {section}", () => window.FindFirstDescendant(c => c.ByAutomationId("section:" + section)));
        item.Patterns.SelectionItem.Pattern.Select();
        Eventually(() => item.Patterns.SelectionItem.Pattern.IsSelected.Value, 5);
        Thread.Sleep(300);
    }

    /// <summary>What a user acts on in the page (not the pane, not the title bar).</summary>
    static IEnumerable<AutomationElement> Interactive(Window window)
    {
        var types = new[] { ControlType.Button, ControlType.CheckBox, ControlType.ComboBox, ControlType.Edit, ControlType.Slider,
                            ControlType.Spinner, ControlType.SplitButton };
        return window.FindAllDescendants(c => c.ByFrameworkId("XAML"))
            .Where(e => types.Contains(e.Properties.ControlType.ValueOrDefault) && e.Properties.IsOffscreen.ValueOrDefault == false
                        && !e.AutomationId.StartsWith("section:") && e.AutomationId is not ("TogglePaneButton" or "Close" or "Minimize" or "Maximize"));
    }

    /// <summary>Reached from the keyboard: a tab stop, or a number box's (its own box is; its arrows are its keys).</summary>
    static bool Reachable(AutomationElement element)
    {
        if (element.Properties.IsKeyboardFocusable.ValueOrDefault) return true;
        if (element.AutomationId is "UpSpinButton" or "DownSpinButton") return true;
        return element.Properties.ControlType.ValueOrDefault == ControlType.Spinner
            && element.FindFirstDescendant(c => c.ByControlType(ControlType.Edit))?.Properties.IsKeyboardFocusable.ValueOrDefault == true;
    }

    static string Describe(AutomationElement element) =>
        $"{element.Properties.ControlType.ValueOrDefault} '{element.AutomationId}' '{element.Name}'";

    static JsonObject Config(string path)
    {
        for (var i = 0; ; i++)
        {
            try
            {
                return (JsonObject)JsonNode.Parse(File.ReadAllText(path))!;
            }
            catch (IOException) when (i < 20)
            {
                Thread.Sleep(50);  // the engine writing it
            }
        }
    }

    static void Stop(uint pid)
    {
        if (pid == 0) return;
        try
        {
            using var process = Process.GetProcessById((int)pid);
            if (process.ProcessName == "AllInOneIMEEngine") process.Kill();
        }
        catch (ArgumentException)
        {
        }
    }

    /// <summary>The window as it is on the screen, title bar and Mica included, when it is the one in front (it is never
    /// brought there: another program may be in use; PrintWindow doesn't draw WinUI's content). The app draws each
    /// section itself as well (its screenshots, at the end).</summary>
    static void Capture(Window window, string path)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        if (GetForegroundWindow() != hwnd)
        {
            Say("  not captured (another window is in front): " + Path.GetFileName(path));
            return;
        }
        GetWindowRect(hwnd, out var rect);
        using var bitmap = new Bitmap(rect.Right - rect.Left, rect.Bottom - rect.Top);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, bitmap.Size);
        }
        bitmap.Save(path, ImageFormat.Png);
        Say("  captured " + path);
    }

    // MARK: Checks

    static void Check(string what, bool ok, string? detail = null)
    {
        if (!ok) failures++;
        Say((ok ? "PASS " : "FAIL ") + what + (detail is null || ok && detail.Length > 200 ? "" : ": " + detail));
    }

    static void Say(string line)
    {
        Console.WriteLine(line);
        log.WriteLine(line);
    }

    static bool Eventually(Func<bool> condition, int seconds = 10)
    {
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (true)
        {
            try
            {
                if (condition()) return true;
            }
            catch (Exception) when (DateTime.UtcNow < deadline)
            {
            }
            if (DateTime.UtcNow >= deadline) return false;
            Thread.Sleep(100);
        }
    }

    static T WaitFor<T>(string what, Func<T?> find, int seconds = 10) where T : class
    {
        T? found = null;
        if (Eventually(() => (found = find()) is not null, seconds)) return found!;
        throw new TimeoutException("not found: " + what);
    }

    static T? WaitFor<T>(string what, Func<T?> find, int seconds = 10) where T : struct
    {
        T? found = null;
        if (Eventually(() => (found = find()) is not null, seconds)) return found;
        throw new TimeoutException("not found: " + what);
    }

    sealed record Options(string App, string Engine, string Stub, string Python, string Out)
    {
        public static Options Parse(string[] args)
        {
            string Value(string name) => args.SkipWhile(a => a != name).Skip(1).FirstOrDefault() ?? throw new ArgumentException(name + " is needed");
            return new Options(Value("--app"), Value("--engine"), Value("--stub"), Value("--python"), Value("--out"));
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    static extern bool SetProcessDpiAwarenessContext(int context);
}
