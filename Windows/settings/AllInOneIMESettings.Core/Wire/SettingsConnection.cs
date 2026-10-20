using AllInOneIME.Settings.Document;

namespace AllInOneIME.Settings.Wire;

/// <summary>Where the window is with the engine.</summary>
public enum ConnectionState
{
    Connecting,
    Connected,
    /// <summary>The engine went away (restarted, updated): connecting again.</summary>
    Reconnecting,
    /// <summary>It can't be reached (not installed, won't start, doesn't answer) or refuses this window.</summary>
    Unavailable,
}

/// <summary>
/// The window's session with the engine: connects (the engine started if it isn't running), keeps the latest document
/// (by revision: an answer that comes late never replaces a newer one), fetches it again when the engine says it changed
/// (one fetch at a time, as many changes as came meanwhile), and connects again when the engine goes away. Its events
/// come through <c>post</c> (the window's thread).
/// </summary>
public sealed class SettingsConnection : IAsyncDisposable
{
    readonly Func<CancellationToken, Task<IFrameTransport>> open;
    readonly Func<Action, bool> post;
    readonly string clientVersion;
    readonly CancellationTokenSource stopping = new();
    SettingsClient? client;
    bool fetching, fetchAgain;
    int generation;

    /// <param name="open">The engine's pipe, connected and checked (<see cref="EngineConnector.ConnectAsync"/>).</param>
    /// <param name="post">Runs an action on the window's thread.</param>
    public SettingsConnection(Func<CancellationToken, Task<IFrameTransport>> open, Func<Action, bool> post, string clientVersion)
    {
        this.open = open;
        this.post = post;
        this.clientVersion = clientVersion;
    }

    public ConnectionState State { get; private set; } = ConnectionState.Connecting;
    /// <summary>Why it is <see cref="ConnectionState.Unavailable"/>.</summary>
    public Exception? Problem { get; private set; }
    public SettingsDocument? Document { get; private set; }
    public ulong Revision { get; private set; }

    /// <summary>The state changed.</summary>
    public event Action? StateChanged;
    /// <summary>A newer document: from an answer (given) or fetched after a change elsewhere (null).</summary>
    public event Action<SettingsAnswer?>? DocumentChanged;

    /// <summary>The delays before each new try after the engine went away (§2.5's backoff).</summary>
    public IReadOnlyList<TimeSpan> Backoff { get; init; } =
        [TimeSpan.Zero, TimeSpan.FromMilliseconds(250), TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5)];

    /// <summary>Connects and fetches the document; on failure, <see cref="ConnectionState.Unavailable"/>.</summary>
    public async Task StartAsync()
    {
        SetState(Document is null ? ConnectionState.Connecting : ConnectionState.Reconnecting, null);
        try
        {
            await ConnectAsync().ConfigureAwait(false);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            SetState(ConnectionState.Unavailable, error);
        }
    }

    async Task ConnectAsync()
    {
        var transport = await open(stopping.Token).ConfigureAwait(false);
        var connected = await SettingsClient.ConnectAsync(transport, clientVersion, stopping.Token).ConfigureAwait(false);
        var mine = Interlocked.Increment(ref generation);
        connected.SettingsChanged += revision => post(() => Changed(revision));
        connected.Closed += why => post(() => Lost(mine, why));
        client = connected;
        var answer = await connected.GetAsync(stopping.Token).ConfigureAwait(false);
        post(() =>
        {
            Apply(answer, force: true);
            SetState(ConnectionState.Connected, null);
        });
    }

    /// <summary>Sends a change or an action; the answer's document is shown if it is the newest. Null when there is no
    /// connection now (the window says so already).</summary>
    public async Task<SettingsAnswer?> SendAsync(SettingsRequest request)
    {
        var current = client;
        if (current is null || State != ConnectionState.Connected) return null;
        var answer = await current.SendAsync(request, stopping.Token).ConfigureAwait(true);
        Apply(answer, force: false);
        return answer;
    }

    void Apply(SettingsAnswer answer, bool force)
    {
        if (!force && answer.Revision < Revision) return;
        var changed = force || answer.Revision != Revision || Document is null
            || !System.Text.Json.Nodes.JsonNode.DeepEquals(Document.Json, answer.Document.Json);
        Revision = answer.Revision;
        Document = answer.Document;
        if (changed || answer.Problem is not null || answer.Message is not null) DocumentChanged?.Invoke(answer);
    }

    /// <summary>The engine says the settings changed: fetched again, once at a time.</summary>
    void Changed(ulong revision)
    {
        if (revision <= Revision) return;
        if (fetching)
        {
            fetchAgain = true;
            return;
        }
        _ = FetchAsync();
    }

    async Task FetchAsync()
    {
        fetching = true;
        try
        {
            do
            {
                fetchAgain = false;
                var current = client;
                if (current is null) return;
                var answer = await current.GetAsync(stopping.Token).ConfigureAwait(true);
                if (answer.Revision >= Revision)
                {
                    var newer = answer.Revision > Revision;
                    Revision = answer.Revision;
                    Document = answer.Document;
                    if (newer) DocumentChanged?.Invoke(null);
                }
            } while (fetchAgain);
        }
        catch (WireException)
        {
            // The connection went away: Lost connects again.
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            fetching = false;
        }
    }

    /// <summary>The engine went away: connected again, with the backoff.</summary>
    void Lost(int lostGeneration, Exception? why)
    {
        if (lostGeneration != generation || stopping.IsCancellationRequested) return;
        client = null;
        SetState(ConnectionState.Reconnecting, why);
        _ = ReconnectAsync();
    }

    async Task ReconnectAsync()
    {
        for (var attempt = 0; !stopping.IsCancellationRequested; attempt++)
        {
            try
            {
                await Task.Delay(Backoff[Math.Min(attempt, Backoff.Count - 1)], stopping.Token).ConfigureAwait(false);
                await ConnectAsync().ConfigureAwait(false);
                return;
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception error) when (attempt >= 8)
            {
                post(() => SetState(ConnectionState.Unavailable, error));
                return;
            }
            catch (Exception)
            {
            }
        }
    }

    void SetState(ConnectionState state, Exception? problem)
    {
        if (!post(() =>
        {
            State = state;
            Problem = problem;
            StateChanged?.Invoke();
        }))
        {
            State = state;
            Problem = problem;
        }
    }

    public async ValueTask DisposeAsync()
    {
        stopping.Cancel();
        if (client is { } current) await current.DisposeAsync().ConfigureAwait(false);
        client = null;
    }
}
