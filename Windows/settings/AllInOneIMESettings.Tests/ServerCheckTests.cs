using System.ComponentModel;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using AllInOneIME.Settings.Wire;
using Xunit;

namespace AllInOneIME.Settings.Tests;

/// <summary>
/// The server check (§2.1) against real pipes: one this user's process at its own integrity serves passes; one a
/// low-integrity process made first (a squatter: what a sandboxed or low-integrity program of the same user could do,
/// waiting for the Settings app and its keys) is refused before anything is sent.
/// </summary>
public class ServerCheckTests
{
    static string Name() => "aio-settings-servercheck-" + Guid.NewGuid().ToString("N");

    [Fact]
    public async Task ThisUsersPipeAtItsIntegrityPasses()
    {
        var name = Name();
        await using var server = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Message, PipeOptions.Asynchronous);
        var waiting = server.WaitForConnectionAsync();
        await using var transport = await PipeTransport.ConnectAsync(name, TimeSpan.FromSeconds(10), CancellationToken.None);
        await waiting;
    }

    [Fact]
    public async Task ALowIntegritySquatterIsRefused()
    {
        var name = Name();
        using var squatter = LowIntegrity.Start(
            $"powershell.exe -NoProfile -NonInteractive -Command \"$p = New-Object System.IO.Pipes.NamedPipeServerStream('{name}', " +
            "[System.IO.Pipes.PipeDirection]::InOut, 4, [System.IO.Pipes.PipeTransmissionMode]::Message); $p.WaitForConnection(); Start-Sleep -Seconds 30\"");
        try
        {
            Assert.Equal(0x1000u, LowIntegrity.Of(squatter));
            // Connected (the squatter waits for it), then refused by the check: its server process is at low integrity.
            var error = await Assert.ThrowsAsync<WireException>(() => PipeTransport.ConnectAsync(name, TimeSpan.FromSeconds(30), CancellationToken.None));
            Assert.Equal("serverCheck", error.Code);
            Assert.Contains("integrity is 0x1000", error.Message);
        }
        finally
        {
            try { squatter.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
        }
    }

    /// <summary>A process started with this one's token at low integrity (S-1-16-4096), as a sandboxed program runs.</summary>
    static class LowIntegrity
    {
        public static Process Start(string commandLine)
        {
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TokenDuplicate | TokenQuery | TokenAdjustDefault | TokenAssignPrimary, out var token))
            {
                throw new Win32Exception();
            }
            IntPtr low = IntPtr.Zero, sid = IntPtr.Zero, label = IntPtr.Zero;
            try
            {
                if (!DuplicateTokenEx(token, MaximumAllowed, IntPtr.Zero, 2 /* SecurityImpersonation */, 1 /* TokenPrimary */, out low))
                {
                    throw new Win32Exception();
                }
                if (!ConvertStringSidToSidW("S-1-16-4096", out sid)) throw new Win32Exception();
                // TOKEN_MANDATORY_LABEL: a SID_AND_ATTRIBUTES (the SID, SE_GROUP_INTEGRITY).
                label = Marshal.AllocHGlobal(IntPtr.Size * 2);
                Marshal.WriteIntPtr(label, sid);
                Marshal.WriteInt32(label, IntPtr.Size, 0x20);
                if (!SetTokenInformation(low, 25 /* TokenIntegrityLevel */, label, (uint)(IntPtr.Size * 2 + GetLengthSid(sid)))) throw new Win32Exception();
                var startup = new StartupInfo { cb = Marshal.SizeOf<StartupInfo>() };
                if (!CreateProcessAsUserW(low, null, commandLine, IntPtr.Zero, IntPtr.Zero, false, 0x08000000 /* CREATE_NO_WINDOW */,
                                          IntPtr.Zero, null, ref startup, out var info))
                {
                    throw new Win32Exception();
                }
                CloseHandle(info.hThread);
                CloseHandle(info.hProcess);
                return Process.GetProcessById(info.dwProcessId);
            }
            finally
            {
                if (label != IntPtr.Zero) Marshal.FreeHGlobal(label);
                if (sid != IntPtr.Zero) LocalFree(sid);
                if (low != IntPtr.Zero) CloseHandle(low);
                CloseHandle(token);
            }
        }

        /// <summary>The integrity level's RID of <paramref name="process"/>.</summary>
        public static uint Of(Process process)
        {
            if (!OpenProcessToken(process.Handle, TokenQuery, out var token)) throw new Win32Exception();
            try
            {
                GetTokenInformation(token, 25, IntPtr.Zero, 0, out var size);
                var buffer = Marshal.AllocHGlobal((int)size);
                try
                {
                    if (!GetTokenInformation(token, 25, buffer, size, out _)) throw new Win32Exception();
                    var sid = Marshal.ReadIntPtr(buffer);
                    var count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                    return (uint)Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
            finally
            {
                CloseHandle(token);
            }
        }

        const uint TokenAssignPrimary = 0x0001, TokenDuplicate = 0x0002, TokenQuery = 0x0008, TokenAdjustDefault = 0x0080;
        const uint MaximumAllowed = 0x02000000;

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

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool DuplicateTokenEx(IntPtr token, uint access, IntPtr attributes, int level, int type, out IntPtr duplicate);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool ConvertStringSidToSidW(string sid, out IntPtr result);

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool SetTokenInformation(IntPtr token, int kind, IntPtr information, uint length);

        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr information, uint length, out uint needed);

        [DllImport("advapi32.dll")]
        static extern int GetLengthSid(IntPtr sid);

        [DllImport("advapi32.dll")]
        static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

        [DllImport("advapi32.dll")]
        static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessAsUserW(IntPtr token, string? application, string commandLine, IntPtr processAttributes,
                                                IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string? directory,
                                                ref StartupInfo startup, out ProcessInformation information);

        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr memory);
    }
}
