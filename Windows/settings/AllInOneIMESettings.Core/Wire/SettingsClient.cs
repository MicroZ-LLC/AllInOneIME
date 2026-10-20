using System.Collections.Concurrent;
using System.Text.Json.Nodes;
using AllInOneIME.Settings.Document;

namespace AllInOneIME.Settings.Wire;

/// <summary>
/// The Settings app's end of the wire (§12): <c>hello</c> with the <c>settings</c> capability, then
/// <c>settingsGet</c>, <c>settingsSet</c> and <c>settingsAction</c>, each answered by a <c>settings</c> frame (matched
/// by <c>re</c>: an action that takes a while may be answered after others), and <c>settingsChanged</c> pushed after
/// any change. It opens no sessions. A key given to <see cref="ActionAsync"/> goes into one frame and nowhere else:
/// nothing here logs a value.
/// </summary>
public sealed class SettingsClient : IAsyncDisposable
{
    readonly IFrameTransport transport;
    readonly CancellationTokenSource stopping = new();
    readonly ConcurrentDictionary<uint, TaskCompletionSource<JsonObject>> waiting = new();
    Task? reader;
    uint lastId;
    int closed;

    SettingsClient(IFrameTransport transport) => this.transport = transport;

    /// <summary>The engine's welcome: its version and pid.</summary>
    public string Engine { get; private set; } = "";
    public uint EnginePid { get; private set; }

    /// <summary>After any change of the settings, with the new revision (on the reader's thread).</summary>
    public event Action<ulong>? SettingsChanged;

    /// <summary>The engine is gone (a broken pipe, <c>bye</c>, a fatal error), once (on the reader's thread).</summary>
    public event Action<Exception?>? Closed;

    /// <summary>How long a request done at once may take; one that takes a while (a test, a download) has
    /// <see cref="LongRequestTimeout"/>.</summary>
    public TimeSpan RequestTimeout { get; set; } = TimeSpan.FromSeconds(15);
    public TimeSpan LongRequestTimeout { get; set; } = TimeSpan.FromMinutes(5);

    /// <summary>Says hello on <paramref name="transport"/> and waits for the welcome; throws
    /// <see cref="WireException"/> <c>notGranted</c> when the engine doesn't give this client the settings.</summary>
    public static async Task<SettingsClient> ConnectAsync(IFrameTransport transport, string clientVersion, CancellationToken cancellation)
    {
        var client = new SettingsClient(transport);
        try
        {
            var hello = new JsonObject
            {
                ["v"] = WireFrame.Version, ["id"] = client.NextId(), ["type"] = "hello", ["versions"] = new JsonArray(WireFrame.Version),
                ["client"] = "settings/" + clientVersion, ["platform"] = "win", ["arch"] = "x64", ["pid"] = Environment.ProcessId,
                ["capabilities"] = new JsonArray("settings"),
            };
            await transport.WriteAsync(WireFrame.Encode(hello), cancellation).ConfigureAwait(false);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            var message = await transport.ReadAsync(timeout.Token).ConfigureAwait(false)
                ?? throw new WireException("closed", "the engine closed the pipe before its welcome");
            var welcome = WireFrame.Decode(message);
            var type = (string?)welcome["type"];
            if (type == "error") throw new WireException((string?)welcome["code"] ?? "error", (string?)welcome["message"] ?? "");
            if (type != "welcome") throw new WireException("badMessage", $"a {type} frame instead of the welcome");
            var capabilities = welcome["capabilities"] as JsonArray;
            if (capabilities?.Any(c => (string?)c == "settings") != true)
            {
                throw new WireException("notGranted", "the engine doesn't give this client the settings");
            }
            client.Engine = (string?)welcome["engine"] ?? "";
            client.EnginePid = welcome["enginePid"] is JsonValue pid && pid.TryGetValue<uint>(out var number) ? number : 0;
            client.reader = Task.Run(client.ReadLoop);
            return client;
        }
        catch
        {
            await client.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    /// <summary>The settings now.</summary>
    public Task<SettingsAnswer> GetAsync(CancellationToken cancellation = default) =>
        RequestAsync(new JsonObject { ["type"] = "settingsGet" }, RequestTimeout, cancellation);

    /// <summary>One change: <paramref name="value"/> may be null (a text unset, "follow the system"), which is sent as
    /// <c>null</c>: a value, not a missing one. Made on what the window showed (§12.4): <paramref name="shown"/>, a list
    /// as it was shown (the value is then an edit of it, merged with what changed elsewhere), and
    /// <paramref name="revision"/>, the document's (refused <c>stale</c> when the settings have moved on).</summary>
    public Task<SettingsAnswer> SetAsync(string field, JsonNode? value, CancellationToken cancellation = default,
                                         JsonNode? shown = null, ulong? revision = null)
    {
        var frame = new JsonObject { ["type"] = "settingsSet", ["field"] = field, ["value"] = value?.DeepClone() };
        if (shown is not null) frame["shown"] = shown.DeepClone();
        if (revision is not null) frame["revision"] = revision.Value;
        return RequestAsync(frame, RequestTimeout, cancellation);
    }

    /// <summary>One of a field's actions. A test, a browse and an install take a while: answered when done.</summary>
    public Task<SettingsAnswer> ActionAsync(SettingsActionRequest action, CancellationToken cancellation = default)
    {
        var frame = new JsonObject { ["type"] = "settingsAction", ["field"] = action.Field, ["action"] = action.Action };
        if (action.Item is not null) frame["item"] = action.Item;
        if (action.Value is not null) frame["value"] = action.Value.DeepClone();
        if (action.Key is not null) frame["key"] = action.Key;
        return RequestAsync(frame, action.TakesAWhile ? LongRequestTimeout : RequestTimeout, cancellation);
    }

    /// <summary>Sends <paramref name="request"/>: a set or an action.</summary>
    public Task<SettingsAnswer> SendAsync(SettingsRequest request, CancellationToken cancellation = default) => request switch
    {
        SettingsSetRequest set => SetAsync(set.Field, set.Value, cancellation, set.Shown, set.Revision),
        SettingsActionRequest action => ActionAsync(action, cancellation),
        _ => throw new ArgumentException("an unknown request", nameof(request)),
    };

    async Task<SettingsAnswer> RequestAsync(JsonObject frame, TimeSpan timeout, CancellationToken cancellation)
    {
        if (Volatile.Read(ref closed) != 0) throw new WireException("closed", "the connection to the engine is closed");
        var id = NextId();
        frame["v"] = WireFrame.Version;
        frame["id"] = id;
        var answer = new TaskCompletionSource<JsonObject>(TaskCreationOptions.RunContinuationsAsynchronously);
        waiting[id] = answer;
        try
        {
            var bytes = WireFrame.Encode(frame);
            frame.Remove("key");  // the key is in the bytes only, and they are cleared once written
            try
            {
                await transport.WriteAsync(bytes, cancellation).ConfigureAwait(false);
            }
            finally
            {
                Array.Clear(bytes);
            }
            using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancellation, stopping.Token);
            limit.CancelAfter(timeout);
            JsonObject reply;
            try
            {
                reply = await answer.Task.WaitAsync(limit.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
            {
                throw Volatile.Read(ref closed) != 0
                    ? new WireException("closed", "the connection to the engine closed")
                    : new WireException("timeout", $"no answer to a {(string?)frame["type"]} in {timeout.TotalSeconds:0} s");
            }
            if ((string?)reply["type"] == "error")
            {
                throw new WireException((string?)reply["code"] ?? "error", (string?)reply["message"] ?? "");
            }
            return SettingsAnswer.Parse(reply);
        }
        finally
        {
            waiting.TryRemove(id, out _);
        }
    }

    uint NextId() => Interlocked.Increment(ref lastId);

    async Task ReadLoop()
    {
        Exception? why = null;
        try
        {
            while (!stopping.IsCancellationRequested)
            {
                var message = await transport.ReadAsync(stopping.Token).ConfigureAwait(false);
                if (message is null) break;
                var frame = WireFrame.Decode(message);
                var type = (string?)frame["type"];
                var re = frame["re"]?.GetValue<uint>();
                if (re is uint id && waiting.TryGetValue(id, out var answer))
                {
                    answer.TrySetResult(frame);
                }
                else if (type == "settingsChanged")
                {
                    SettingsChanged?.Invoke(frame["revision"]?.GetValue<ulong>() ?? 0);
                }
                else if (type == "bye")
                {
                    why = new WireException("bye", (string?)frame["reason"] ?? "bye");
                    break;
                }
                else if (type == "error" && re is null)
                {
                    why = new WireException((string?)frame["code"] ?? "error", (string?)frame["message"] ?? "");
                    break;
                }
                // Anything else (a type a later engine sends) is ignored (§9).
            }
        }
        catch (OperationCanceledException) when (stopping.IsCancellationRequested)
        {
        }
        catch (Exception error)
        {
            why = error;
        }
        Close(why);
    }

    void Close(Exception? why)
    {
        if (Interlocked.Exchange(ref closed, 1) != 0) return;
        foreach (var answer in waiting.Values) answer.TrySetException(new WireException("closed", "the connection to the engine closed"));
        Closed?.Invoke(why);
    }

    public async ValueTask DisposeAsync()
    {
        stopping.Cancel();
        await transport.DisposeAsync().ConfigureAwait(false);
        if (reader is not null)
        {
            try { await reader.ConfigureAwait(false); } catch { }
        }
        Interlocked.Exchange(ref closed, 1);
        stopping.Dispose();
    }
}

/// <summary>What the window asks of the engine: a change or an action.</summary>
public abstract class SettingsRequest(string field)
{
    public string Field { get; } = field;
}

/// <summary><c>settingsSet</c>: a field's new value (null is a value); for a list, the list as the window showed it
/// (<c>shown</c>), so that what changed elsewhere meanwhile is kept (§12.4).</summary>
public sealed class SettingsSetRequest(string field, JsonNode? value, JsonNode? shown = null, ulong? revision = null) : SettingsRequest(field)
{
    public JsonNode? Value { get; } = value;
    /// <summary>The list as the window showed it (or its line), the value being the window's edit of it.</summary>
    public JsonNode? Shown { get; } = shown;
    /// <summary>The revision of the document the change was made on.</summary>
    public ulong? Revision { get; } = revision;

    public override string ToString() => $"set {Field}";
}

/// <summary><c>settingsAction</c>. Its <see cref="Key"/> (a key, a token, a password being saved) is never shown by
/// <see cref="ToString"/> nor kept after it is sent.</summary>
public sealed class SettingsActionRequest(string field, string action, string? item = null, JsonNode? value = null, string? key = null)
    : SettingsRequest(field)
{
    public string Action { get; } = action;
    public string? Item { get; } = item;
    public JsonNode? Value { get; } = value;
    public string? Key { get; } = key;

    /// <summary>A test, a download, an install: answered when done (§12.5).</summary>
    public bool TakesAWhile => Action is "test" or "browse" or "install";

    public override string ToString() => $"{Action} on {Field}" + (Item is null ? "" : $" ({Item})");
}

/// <summary>A <c>settings</c> frame: the settings as they are after the request, and what was refused or said.</summary>
public sealed class SettingsAnswer
{
    public required ulong Revision { get; init; }
    public required SettingsDocument Document { get; init; }
    public SettingsProblem? Problem { get; init; }
    /// <summary>What an action that worked says: a test's outcome, "✓ 1.2 s: …".</summary>
    public string? Message { get; init; }

    /// <summary>The answer in <paramref name="frame"/>; a frame that isn't one (another type, a field of the wrong
    /// type) is a <see cref="WireException"/> <c>badMessage</c>, as any frame the window can't read.</summary>
    public static SettingsAnswer Parse(JsonObject frame)
    {
        if (SettingsDocument.Text(frame["type"]) != "settings")
        {
            throw new WireException("badMessage", $"a {SettingsDocument.Text(frame["type"]) ?? "nameless"} frame, not settings");
        }
        try
        {
            var problem = frame["problem"] as JsonObject;
            return new SettingsAnswer
            {
                Revision = frame["revision"]?.GetValue<ulong>() ?? 0,
                Document = SettingsDocument.Parse(frame["document"] as JsonObject ?? throw new WireException("badMessage", "no document")),
                Problem = problem is null ? null : new SettingsProblem(SettingsDocument.Text(problem["code"]) ?? "",
                                                                       SettingsDocument.Text(problem["field"]),
                                                                       SettingsDocument.Text(problem["message"]) ?? ""),
                Message = SettingsDocument.Text(frame["message"]),
            };
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException or System.Text.Json.JsonException)
        {
            throw new WireException("badMessage", "a settings frame that can't be read: " + error.GetType().Name);
        }
    }
}

/// <summary>A change or action refused (§12.4): <c>unknownField</c>, <c>badValue</c>, <c>notChangeable</c>,
/// <c>configBroken</c>, <c>failed</c>, <c>cancelled</c> (an action stopped), <c>stale</c> (made on what the settings
/// have moved on from: nothing changed, the document is as they are now); its message is for the user, in the interface
/// language.</summary>
public sealed record SettingsProblem(string Code, string? Field, string Message)
{
    /// <summary>An action that takes a while stopped by <c>cancel</c> (or by the same action again): not an error.</summary>
    public bool IsCancelled => Code == "cancelled";
    /// <summary>Made on settings that changed meanwhile: the user makes the change again on the document now.</summary>
    public bool IsStale => Code == "stale";
}
