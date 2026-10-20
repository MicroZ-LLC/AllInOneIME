using System.IO.Pipes;
using System.Security.Principal;

namespace AllInOneIME.Settings.Wire;

/// <summary>Whole frames in and out: the engine's pipe, or a test's stand-in.</summary>
public interface IFrameTransport : IAsyncDisposable
{
    /// <summary>Writes one frame (its prefix and body).</summary>
    Task WriteAsync(byte[] frame, CancellationToken cancellation);

    /// <summary>The next message, whole; null when the other end closed.</summary>
    Task<byte[]?> ReadAsync(CancellationToken cancellation);
}

/// <summary>
/// The engine's named pipe in message mode (§2.1): one frame per message. Opened for identification only (the engine
/// may learn who the client is, never act as it), then checked to be the real engine (<see cref="ServerCheck"/>).
/// </summary>
public sealed class PipeTransport : IFrameTransport
{
    readonly NamedPipeClientStream pipe;
    readonly SemaphoreSlim writing = new(1, 1);

    PipeTransport(NamedPipeClientStream pipe) => this.pipe = pipe;

    /// <summary>Connects to <paramref name="pipeName"/> (<c>\\.\pipe\NAME</c> or <c>NAME</c>) within
    /// <paramref name="timeout"/>, and checks its server. Throws <see cref="FileNotFoundException"/>-like
    /// <see cref="TimeoutException"/> when nothing serves it, <see cref="WireException"/> (<c>serverCheck</c>) when it
    /// isn't the engine.</summary>
    public static async Task<PipeTransport> ConnectAsync(string pipeName, TimeSpan timeout, CancellationToken cancellation)
    {
        var pipe = new NamedPipeClientStream(".", PipeNames.ShortName(pipeName), PipeDirection.InOut, PipeOptions.Asynchronous,
                                             TokenImpersonationLevel.Identification);
        try
        {
            await pipe.ConnectAsync((int)timeout.TotalMilliseconds, cancellation).ConfigureAwait(false);
            pipe.ReadMode = PipeTransmissionMode.Message;
            ServerCheck.Verify(pipe.SafePipeHandle);
            return new PipeTransport(pipe);
        }
        catch
        {
            await pipe.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    public async Task WriteAsync(byte[] frame, CancellationToken cancellation)
    {
        await writing.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            await pipe.WriteAsync(frame, cancellation).ConfigureAwait(false);
            await pipe.FlushAsync(cancellation).ConfigureAwait(false);
        }
        finally
        {
            writing.Release();
        }
    }

    public async Task<byte[]?> ReadAsync(CancellationToken cancellation)
    {
        var buffer = new byte[64 * 1024];
        var size = 0;
        while (true)
        {
            if (size == buffer.Length)
            {
                if (buffer.Length >= WireFrame.MaxEngineBody + 4) throw new WireException("tooLarge", "a message over 1 MiB");
                Array.Resize(ref buffer, Math.Min(buffer.Length * 2, WireFrame.MaxEngineBody + 4));
            }
            var read = await pipe.ReadAsync(buffer.AsMemory(size), cancellation).ConfigureAwait(false);
            if (read == 0 && size == 0) return null;
            size += read;
            if (pipe.IsMessageComplete) return buffer[..size];
            if (read == 0) return null;
        }
    }

    public async ValueTask DisposeAsync()
    {
        await pipe.DisposeAsync().ConfigureAwait(false);
        writing.Dispose();
    }
}
