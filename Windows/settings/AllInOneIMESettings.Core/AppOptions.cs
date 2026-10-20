namespace AllInOneIME.Settings;

/// <summary>
/// The Settings app's command line. A user starts it with none (the Start menu, @settings). The rest is for tests and
/// is in no help text: another engine's pipe (and the engine to start on it), the theme forced, the window drawn into
/// PNG files.
/// </summary>
///
///     AllInOneIMESettings.exe [--pipe NAME] [--engine EXE [--engine-args "ARGS"]] [--theme light|dark]
///                             [--section ID] [--screenshots DIR] [--size WxH]
public sealed record AppOptions
{
    /// <summary>A test engine's pipe instead of the user's (<c>\\.\pipe\NAME</c> or <c>NAME</c>).</summary>
    public string? Pipe { get; init; }
    /// <summary>The engine to start when nothing serves the pipe (a test's; else the installed one).</summary>
    public string? Engine { get; init; }
    public string EngineArguments { get; init; } = "";
    /// <summary><c>light</c> or <c>dark</c> instead of Windows' own.</summary>
    public string? Theme { get; init; }
    /// <summary>The section shown first.</summary>
    public string? Section { get; init; }
    /// <summary>Draws every section into PNG files in this folder, then quits.</summary>
    public string? Screenshots { get; init; }
    /// <summary>The window's size in device-independent pixels.</summary>
    public (int width, int height)? Size { get; init; }

    public static AppOptions Parse(IReadOnlyList<string> arguments)
    {
        var options = new AppOptions();
        for (var i = 0; i < arguments.Count; i++)
        {
            string Value() => i + 1 < arguments.Count ? arguments[++i] : throw new ArgumentException($"{arguments[i]} needs a value");
            options = arguments[i] switch
            {
                "--pipe" => options with { Pipe = Value() },
                "--engine" => options with { Engine = Value() },
                "--engine-args" => options with { EngineArguments = Value() },
                "--theme" => options with { Theme = Value() is var theme and ("light" or "dark") ? theme : throw new ArgumentException("--theme is light or dark") },
                "--section" => options with { Section = Value() },
                "--screenshots" => options with { Screenshots = Value() },
                "--size" => options with { Size = ParseSize(Value()) },
                _ => options,  // what Windows or a later version passes: ignored
            };
        }
        return options;
    }

    static (int, int) ParseSize(string text)
    {
        var parts = text.Split('x', 'X');
        return parts.Length == 2 && int.TryParse(parts[0], out var w) && int.TryParse(parts[1], out var h) && w > 0 && h > 0
            ? (w, h) : throw new ArgumentException("--size is WIDTHxHEIGHT");
    }
}
