using System.Security.Principal;

namespace AllInOneIME.Settings.Wire;

/// <summary>The engine's names (§2.1, §2.5), as the engine and the text service make them.</summary>
public static class PipeNames
{
    const string Prefix = @"\\.\pipe\";

    static string UserSid => WindowsIdentity.GetCurrent().User?.Value ?? throw new InvalidOperationException("no user SID");

    /// <summary>The user's engine: <c>\\.\pipe\AllInOneIME-&lt;SID&gt;-v1</c>.</summary>
    public static string UserPipe => Prefix + "AllInOneIME-" + UserSid + "-v1";

    /// <summary>A pipe's full name: <c>NAME</c> → <c>\\.\pipe\NAME</c>.</summary>
    public static string Full(string pipe) => pipe.StartsWith(@"\\", StringComparison.Ordinal) ? pipe : Prefix + pipe;

    /// <summary>The name without <c>\\.\pipe\</c>, as .NET's pipe classes take it.</summary>
    public static string ShortName(string pipe) =>
        pipe.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) ? pipe[Prefix.Length..] : pipe;

    /// <summary>The engine's single-instance mutex for <paramref name="pipe"/>: the user's engine's
    /// (<c>Local\AllInOneIME-Engine-&lt;SID&gt;</c>), or a test engine's on a pipe of its own (its name added, as the
    /// engine's <c>--pipe</c> makes it).</summary>
    public static string EngineMutex(string pipe)
    {
        var mutex = @"Local\AllInOneIME-Engine-" + UserSid;
        if (string.Equals(Full(pipe), UserPipe, StringComparison.OrdinalIgnoreCase)) return mutex;
        var name = ShortName(Full(pipe)).Split('\\').Last();
        return mutex + "-" + new string(name.Select(c => char.IsLetterOrDigit(c) || c == '-' ? c : '_').ToArray());
    }

    /// <summary>The Settings app's own single-instance event, one per engine it talks to.</summary>
    public static string SettingsInstance(string pipe) =>
        @"Local\AllInOneIME-Settings-" + new string(ShortName(Full(pipe)).Select(c => char.IsLetterOrDigit(c) || c == '-' ? c : '_').ToArray());
}
