using System.Text.Json.Nodes;
using AllInOneIME.Settings.Wire;
using Xunit;

namespace AllInOneIME.Settings.Tests;

/// <summary>The window's session with the engine: the newest document kept, a change elsewhere fetched once, the engine
/// started when it isn't running, connected again when it goes away; and what the window says when it can't be reached.</summary>
public class ConnectionTests
{
    static JsonObject Document(string name = "golden-01-settingsGet") => (JsonObject)Fixtures.Answer(name)["document"]!;

    sealed class Session
    {
        public readonly List<FakeEngine> Engines = [];
        public readonly List<MemoryPipe> Pipes = [];
        public readonly SettingsConnection Connection;
        public int Changes;

        public Session()
        {
            Connection = new SettingsConnection(_ =>
            {
                var pipe = new MemoryPipe();
                lock (Pipes)
                {
                    Pipes.Add(pipe);
                    Engines.Add(new FakeEngine(pipe.Engine));
                }
                return Task.FromResult(pipe.Client);
            }, action => { action(); return true; }, "test")
            {
                Backoff = [TimeSpan.Zero, TimeSpan.FromMilliseconds(20)],
            };
            Connection.DocumentChanged += _ => Interlocked.Increment(ref Changes);
        }

        public FakeEngine Engine(int index)
        {
            for (var i = 0; i < 500; i++)
            {
                lock (Pipes)
                {
                    if (Engines.Count > index) return Engines[index];
                }
                Thread.Sleep(10);
            }
            throw new TimeoutException("no connection " + index);
        }
    }

    static async Task WaitFor(Func<bool> condition)
    {
        for (var i = 0; i < 300 && !condition(); i++) await Task.Delay(10);
        Assert.True(condition());
    }

    [Fact]
    public async Task ConnectsFetchesAndKeepsTheNewest()
    {
        var session = new Session();
        var starting = session.Connection.StartAsync();
        var engine = session.Engine(0);
        await engine.WelcomeAsync();
        await engine.AnswerAsync(await engine.ReceiveAsync(), 1, Document());
        await starting;
        await WaitFor(() => session.Connection.State == ConnectionState.Connected);
        Assert.Equal(1UL, session.Connection.Revision);

        // A change elsewhere: fetched; two notifications while one fetch is under way make one more fetch, not two.
        await engine.SendAsync(new JsonObject { ["type"] = "settingsChanged", ["revision"] = 2 });
        var first = await engine.ReceiveAsync();
        Assert.Equal("settingsGet", (string?)first["type"]);
        await engine.SendAsync(new JsonObject { ["type"] = "settingsChanged", ["revision"] = 3 });
        await engine.SendAsync(new JsonObject { ["type"] = "settingsChanged", ["revision"] = 4 });
        await engine.AnswerAsync(first, 2, Document("golden-02-settingsSet-maxTokens"));
        var second = await engine.ReceiveAsync();
        await engine.AnswerAsync(second, 4, Document("golden-03-settingsSet-maxTokens"));
        await WaitFor(() => session.Connection.Revision == 4);
        Assert.Equal(4, engine.Received.Count);  // hello, the first get, and two fetches

        // An answer older than what is shown doesn't replace it.
        var sending = session.Connection.SendAsync(new SettingsSetRequest("maxTokens", JsonValue.Create(1500)));
        var set = await engine.ReceiveAsync();
        await engine.AnswerAsync(set, 3, Document("golden-01-settingsGet"));
        var answer = await sending;
        Assert.Equal(3UL, answer!.Revision);
        Assert.Equal(4UL, session.Connection.Revision);
    }

    [Fact]
    public async Task TheEngineGoesAwayAndComesBack()
    {
        var session = new Session();
        var starting = session.Connection.StartAsync();
        var engine = session.Engine(0);
        await engine.WelcomeAsync();
        await engine.AnswerAsync(await engine.ReceiveAsync(), 5, Document());
        await starting;
        await WaitFor(() => session.Connection.State == ConnectionState.Connected);

        session.Pipes[0].CloseEngine();
        var again = session.Engine(1);
        Assert.Equal(ConnectionState.Reconnecting, session.Connection.State);
        await again.WelcomeAsync();
        await again.AnswerAsync(await again.ReceiveAsync(), 1, Document());
        await WaitFor(() => session.Connection.State == ConnectionState.Connected);
        // A new engine counts revisions from 1 again: its document is shown.
        Assert.Equal(1UL, session.Connection.Revision);
    }

    [Fact]
    public async Task AnEngineThatCantBeReached()
    {
        var connection = new SettingsConnection(_ => throw new EngineUnavailableException(EngineProblem.NotInstalled, "none"),
                                                action => { action(); return true; }, "test");
        await connection.StartAsync();
        Assert.Equal(ConnectionState.Unavailable, connection.State);
        Assert.Equal(EngineProblem.NotInstalled, ((EngineUnavailableException)connection.Problem!).Problem);
        Assert.Null(await connection.SendAsync(new SettingsSetRequest("typeOut", JsonValue.Create(true))));
    }

    // MARK: Starting the engine

    static string NoPipe() => "aio-settings-test-none-" + Guid.NewGuid().ToString("N");

    [Fact]
    public async Task NoEngineToStart()
    {
        var connector = new EngineConnector { Pipe = NoPipe(), FindEngine = () => null };
        var error = await Assert.ThrowsAsync<EngineUnavailableException>(() => connector.ConnectAsync(CancellationToken.None));
        Assert.Equal(EngineProblem.NotInstalled, error.Problem);
    }

    [Fact]
    public async Task TheEngineIsStartedAndWaitedFor()
    {
        var started = new List<(string, string)>();
        var connector = new EngineConnector
        {
            Pipe = NoPipe(), FindEngine = () => (@"C:\AllInOneIME\AllInOneIMEEngine.exe", "--quiet"),
            Start = (path, arguments) => started.Add((path, arguments)), StartTimeout = TimeSpan.FromMilliseconds(600),
        };
        var error = await Assert.ThrowsAsync<EngineUnavailableException>(() => connector.ConnectAsync(CancellationToken.None));
        Assert.Equal(EngineProblem.NoAnswer, error.Problem);
        Assert.Equal([(@"C:\AllInOneIME\AllInOneIMEEngine.exe", "--quiet")], started);
        Assert.Equal("started", connector.Outcome);
    }

    [Fact]
    public async Task AnEngineStartingIsntStartedAgain()
    {
        var started = 0;
        var connector = new EngineConnector
        {
            Pipe = NoPipe(), FindEngine = () => ("engine.exe", ""), Start = (_, _) => started++, EngineRunning = _ => true,
            StartTimeout = TimeSpan.FromMilliseconds(300),
        };
        await Assert.ThrowsAsync<EngineUnavailableException>(() => connector.ConnectAsync(CancellationToken.None));
        Assert.Equal(0, started);
    }

    [Fact]
    public async Task AnEngineThatWontStart()
    {
        var connector = new EngineConnector
        {
            Pipe = NoPipe(), FindEngine = () => (@"C:\nowhere\AllInOneIMEEngine.exe", ""), Start = EngineConnector.StartDetached,
        };
        var error = await Assert.ThrowsAsync<EngineUnavailableException>(() => connector.ConnectAsync(CancellationToken.None));
        Assert.Equal(EngineProblem.CouldNotStart, error.Problem);
    }
}
