using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AllInOneIME.Settings.Wire;

/// <summary>
/// Reaches the engine as the text service does (§2.5): its pipe; if nothing serves it, the engine started from
/// <c>HKLM\Software\AllInOneIME</c>, value <c>Engine</c> (unless its single-instance mutex shows it running or
/// starting), and its pipe waited for. Tests give their own pipe, and their own engine to start, if any.
/// </summary>
public sealed class EngineConnector
{
    /// <summary>The pipe: the user's engine's unless a test gives another.</summary>
    public string Pipe { get; init; } = PipeNames.UserPipe;

    /// <summary>The engine to start when nothing serves the pipe: the installed one's path from the registry, or a
    /// test's (with its arguments); none: never started.</summary>
    public Func<(string path, string arguments)?> FindEngine { get; init; } = InstalledEngine;

    /// <summary>How long a started engine has to open its pipe.</summary>
    public TimeSpan StartTimeout { get; init; } = TimeSpan.FromSeconds(15);

    /// <summary>Starts a program (the engine), detached; a test's stand-in records it.</summary>
    public Action<string, string> Start { get; init; } = StartDetached;

    /// <summary>Whether the engine's mutex is held (it is running or starting).</summary>
    public Func<string, bool> EngineRunning { get; init; } = MutexHeld;

    /// <summary>What happened, for the window: <c>connected</c>, <c>started</c> (the engine wasn't running).</summary>
    public string? Outcome { get; private set; }

    /// <summary>The engine's pipe, connected and checked; the engine started first if it isn't running.</summary>
    public async Task<PipeTransport> ConnectAsync(CancellationToken cancellation)
    {
        try
        {
            var transport = await PipeTransport.ConnectAsync(Pipe, TimeSpan.FromMilliseconds(500), cancellation).ConfigureAwait(false);
            Outcome = "connected";
            return transport;
        }
        catch (TimeoutException)
        {
        }
        if (!EngineRunning(PipeNames.EngineMutex(Pipe)))
        {
            var engine = FindEngine() ?? throw new EngineUnavailableException(EngineProblem.NotInstalled, "no engine to start");
            try
            {
                Start(engine.path, engine.arguments);
            }
            catch (Exception error) when (error is Win32Exception or FileNotFoundException or InvalidOperationException)
            {
                throw new EngineUnavailableException(EngineProblem.CouldNotStart, error.Message);
            }
            Outcome = "started";
        }
        var deadline = DateTime.UtcNow + StartTimeout;
        while (true)
        {
            cancellation.ThrowIfCancellationRequested();
            try
            {
                var transport = await PipeTransport.ConnectAsync(Pipe, TimeSpan.FromMilliseconds(250), cancellation).ConfigureAwait(false);
                Outcome ??= "connected";
                return transport;
            }
            catch (TimeoutException) when (DateTime.UtcNow < deadline)
            {
            }
            catch (TimeoutException)
            {
                throw new EngineUnavailableException(EngineProblem.NoAnswer, "the engine didn't open its pipe");
            }
        }
    }

    /// <summary>The installed engine: <c>HKLM\Software\AllInOneIME</c>, <c>Engine</c> (the 64-bit view).</summary>
    public static (string path, string arguments)? InstalledEngine()
    {
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var key = machine.OpenSubKey(@"Software\AllInOneIME");
        return key?.GetValue("Engine") is string path && path.Length > 0 && File.Exists(path) ? (path, "") : null;
    }

    /// <summary>As the text service starts it: detached, in a new process group, out of any job this app is in.</summary>
    public static void StartDetached(string path, string arguments)
    {
        const uint DetachedProcess = 0x8, NewProcessGroup = 0x200, UnicodeEnvironment = 0x400, BreakawayFromJob = 0x01000000;
        var command = "\"" + path + "\"" + (arguments.Length > 0 ? " " + arguments : "");
        var startup = new StartupInfo { cb = Marshal.SizeOf<StartupInfo>() };
        var flags = DetachedProcess | NewProcessGroup | UnicodeEnvironment;
        if (!CreateProcess(path, command, IntPtr.Zero, IntPtr.Zero, false, flags | BreakawayFromJob, IntPtr.Zero,
                           Path.GetDirectoryName(path), ref startup, out var info)
            && !CreateProcess(path, command, IntPtr.Zero, IntPtr.Zero, false, flags, IntPtr.Zero, Path.GetDirectoryName(path),
                              ref startup, out info))
        {
            throw new Win32Exception();
        }
        CloseHandle(info.hThread);
        CloseHandle(info.hProcess);
    }

    static bool MutexHeld(string name)
    {
        if (!Mutex.TryOpenExisting(name, out var mutex)) return false;
        mutex.Dispose();
        return true;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo
    {
        public int cb;
        public string? lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInformation
    {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateProcessW")]
    static extern bool CreateProcess(string application, string commandLine, IntPtr processAttributes, IntPtr threadAttributes,
                                     bool inheritHandles, uint flags, IntPtr environment, string? directory,
                                     ref StartupInfo startup, out ProcessInformation information);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
}

public enum EngineProblem
{
    /// <summary>No engine to start: AllInOneIME isn't installed (or its registration is gone).</summary>
    NotInstalled,
    /// <summary>Starting it failed.</summary>
    CouldNotStart,
    /// <summary>Started (or starting), but its pipe never opened.</summary>
    NoAnswer,
}

/// <summary>The engine can't be reached: the window says why, and offers to try again.</summary>
public sealed class EngineUnavailableException(EngineProblem problem, string message) : Exception(message)
{
    public EngineProblem Problem { get; } = problem;
}
