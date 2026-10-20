using System.Text.Json.Nodes;
using System.Threading.Channels;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Wire;

namespace AllInOneIME.Settings.Tests;

/// <summary>Two ends of a pipe in memory: what one writes, the other reads, a message at a time.</summary>
sealed class MemoryPipe
{
    readonly Channel<byte[]> toEngine = Channel.CreateUnbounded<byte[]>();
    readonly Channel<byte[]> toClient = Channel.CreateUnbounded<byte[]>();

    public IFrameTransport Client => new End(toEngine.Writer, toClient.Reader, toEngine.Writer);
    public IFrameTransport Engine => new End(toClient.Writer, toEngine.Reader, toClient.Writer);

    /// <summary>The engine's end closed: the client reads the end of the pipe.</summary>
    public void CloseEngine() => toClient.Writer.TryComplete();

    sealed class End(ChannelWriter<byte[]> output, ChannelReader<byte[]> input, ChannelWriter<byte[]> mine) : IFrameTransport
    {
        public async Task WriteAsync(byte[] frame, CancellationToken cancellation) =>
            await output.WriteAsync(frame.ToArray(), cancellation);

        public async Task<byte[]?> ReadAsync(CancellationToken cancellation)
        {
            try
            {
                return await input.ReadAsync(cancellation);
            }
            catch (ChannelClosedException)
            {
                return null;
            }
        }

        public ValueTask DisposeAsync()
        {
            mine.TryComplete();
            return ValueTask.CompletedTask;
        }
    }
}

/// <summary>A stand-in engine on a <see cref="MemoryPipe"/>: what a test tells it to answer, and what it was sent.</summary>
sealed class FakeEngine
{
    readonly IFrameTransport pipe;
    uint id;

    public FakeEngine(IFrameTransport pipe) => this.pipe = pipe;

    public List<JsonObject> Received { get; } = [];

    public async Task<JsonObject> ReceiveAsync()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var message = await pipe.ReadAsync(timeout.Token) ?? throw new InvalidOperationException("the client closed the pipe");
        var frame = WireFrame.Decode(message);
        Received.Add(frame);
        return frame;
    }

    public Task SendAsync(JsonObject frame)
    {
        frame["v"] = 1;
        frame["id"] = ++id;
        var body = System.Text.Encoding.UTF8.GetBytes(frame.ToJsonString());
        var bytes = new byte[body.Length + 4];
        BitConverter.GetBytes((uint)body.Length).CopyTo(bytes, 0);
        body.CopyTo(bytes, 4);
        return pipe.WriteAsync(bytes, CancellationToken.None);
    }

    /// <summary>Answers a hello with a welcome (with the settings, unless told not to).</summary>
    public async Task WelcomeAsync(bool settings = true)
    {
        var hello = await ReceiveAsync();
        await SendAsync(new JsonObject
        {
            ["re"] = hello["id"]!.GetValue<uint>(), ["type"] = "welcome", ["version"] = 1, ["engine"] = "test", ["enginePid"] = 1,
            ["capabilities"] = settings ? new JsonArray("settings") : new JsonArray(),
            ["limits"] = new JsonObject { ["contextBefore"] = 32, ["selection"] = 10002 },
        });
    }

    /// <summary>A settings answer to <paramref name="request"/> with <paramref name="document"/>.</summary>
    public Task AnswerAsync(JsonObject request, ulong revision, JsonObject document, JsonObject? problem = null, string? message = null)
    {
        var frame = new JsonObject
        {
            ["re"] = request["id"]!.GetValue<uint>(), ["type"] = "settings", ["revision"] = revision, ["document"] = document.DeepClone(),
        };
        if (problem is not null) frame["problem"] = problem;
        if (message is not null) frame["message"] = message;
        return SendAsync(frame);
    }
}

/// <summary>The files the tests read: the documents the engine sent (Documents/), the repository's goldens.</summary>
static class Fixtures
{
    public static string DocumentsFolder => Path.Combine(AppContext.BaseDirectory, "Documents");

    public static IEnumerable<string> DocumentNames =>
        Directory.GetFiles(DocumentsFolder, "*.json").Select(Path.GetFileNameWithoutExtension).OfType<string>().Order();

    /// <summary>A whole <c>settings</c> answer as the engine sent it.</summary>
    public static JsonObject Answer(string name) =>
        (JsonObject)JsonNode.Parse(File.ReadAllText(Path.Combine(DocumentsFolder, name + ".json")))!;

    public static SettingsDocument Document(string name) => SettingsDocument.Parse((JsonObject)Answer(name)["document"]!);

    /// <summary>The repository's file at <paramref name="relative"/> (found up from the tests' folder).</summary>
    public static string Repository(string relative)
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder is not null; folder = folder.Parent)
        {
            var path = Path.Combine(folder.FullName, relative);
            if (File.Exists(path)) return path;
        }
        throw new FileNotFoundException("not in the repository: " + relative);
    }
}
