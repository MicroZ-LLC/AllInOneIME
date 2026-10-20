using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace AllInOneIME.Settings.Wire;

/// <summary>
/// The server check (§2.1, with the spec notes' fix): before a key goes anywhere, the pipe must be the user's engine's.
/// The server is in this session, the pipe's owner is this user, and the server process runs as this user at medium
/// integrity or higher (a pipe a low-integrity squatter made fails this).
/// </summary>
public static partial class ServerCheck
{
    public static void Verify(SafePipeHandle pipe)
    {
        var me = WindowsIdentity.GetCurrent().User ?? throw new WireException("serverCheck", "no user SID");
        if (!GetNamedPipeServerSessionId(pipe, out var serverSession) || !ProcessIdToSessionId((uint)Environment.ProcessId, out var mySession))
        {
            throw new WireException("serverCheck", "can't read the sessions: " + new Win32Exception().Message);
        }
        if (serverSession != mySession) throw new WireException("serverCheck", $"the server is in session {serverSession}, not {mySession}");

        var owner = PipeOwner(pipe);
        if (owner != me) throw new WireException("serverCheck", "the pipe's owner isn't this user");

        if (!GetNamedPipeServerProcessId(pipe, out var pid)) throw new WireException("serverCheck", "no server process id");
        var (user, integrity) = ProcessUser(pid);
        if (user != me) throw new WireException("serverCheck", "the server runs as another user");
        if (integrity < MediumIntegrity) throw new WireException("serverCheck", $"the server's integrity is 0x{integrity:x}");
    }

    const uint MediumIntegrity = 0x2000;

    static SecurityIdentifier PipeOwner(SafePipeHandle pipe)
    {
        var error = GetSecurityInfo(pipe, 6 /* SE_KERNEL_OBJECT */, 1 /* OWNER_SECURITY_INFORMATION */, out var owner,
                                    IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out var descriptor);
        if (error != 0) throw new WireException("serverCheck", "can't read the pipe's owner: " + new Win32Exception((int)error).Message);
        try
        {
            return new SecurityIdentifier(owner);
        }
        finally
        {
            LocalFree(descriptor);
        }
    }

    static (SecurityIdentifier user, uint integrity) ProcessUser(uint pid)
    {
        using var process = OpenProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, false, pid);
        if (process.IsInvalid) throw new WireException("serverCheck", "can't open the server process: " + new Win32Exception().Message);
        if (!OpenProcessToken(process, 0x0008 /* TOKEN_QUERY */, out var token))
        {
            throw new WireException("serverCheck", "can't read the server's token: " + new Win32Exception().Message);
        }
        using (token)
        {
            var user = TokenInformation(token, 1 /* TokenUser */, buffer => new SecurityIdentifier(Marshal.ReadIntPtr(buffer)));
            var integrity = TokenInformation(token, 25 /* TokenIntegrityLevel */, buffer =>
            {
                var sid = Marshal.ReadIntPtr(buffer);
                var count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                return (uint)Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
            });
            return (user, integrity);
        }
    }

    static T TokenInformation<T>(SafeAccessTokenHandle token, int kind, Func<IntPtr, T> read)
    {
        GetTokenInformation(token, kind, IntPtr.Zero, 0, out var size);
        var buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (!GetTokenInformation(token, kind, buffer, size, out _))
            {
                throw new WireException("serverCheck", "can't read the server's token: " + new Win32Exception().Message);
            }
            return read(buffer);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetNamedPipeServerSessionId(SafePipeHandle pipe, out uint session);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ProcessIdToSessionId(uint pid, out uint session);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial SafeProcessHandle OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool OpenProcessToken(SafeProcessHandle process, uint access, out SafeAccessTokenHandle token);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetTokenInformation(SafeAccessTokenHandle token, int kind, IntPtr buffer, uint size, out uint needed);

    [LibraryImport("advapi32.dll")]
    private static partial IntPtr GetSidSubAuthorityCount(IntPtr sid);

    [LibraryImport("advapi32.dll")]
    private static partial IntPtr GetSidSubAuthority(IntPtr sid, uint index);

    [LibraryImport("advapi32.dll")]
    private static partial uint GetSecurityInfo(SafePipeHandle handle, int type, uint information, out IntPtr owner, IntPtr group,
                                                IntPtr dacl, IntPtr sacl, out IntPtr descriptor);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr LocalFree(IntPtr memory);
}
