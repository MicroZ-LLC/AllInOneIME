using System.Text;
using System.Text.Json.Nodes;
using AllInOneIME.Settings.Wire;
using Xunit;

namespace AllInOneIME.Settings.Tests;

/// <summary>The wire client (§12) against a stand-in engine: the settings golden replayed frame by frame, the frames'
/// shape and order, and what a key may and may not leave behind.</summary>
public class SettingsClientTests
{
    /// <summary>The golden (Core/Tests/AllInOneIMEWireTests/WireGoldens/settings.jsonl): each frame the client sends is
    /// the golden's <c>&gt;</c> line (its own ids and values aside), and each answer comes back as its <c>&lt;</c> lines
    /// say, with the documents the engine really sent for them (Documents/golden-*).</summary>
    [Fact]
    public async Task TheSettingsGoldenReplayed()
    {
        var lines = File.ReadAllLines(Fixtures.Repository("Core/Tests/AllInOneIMEWireTests/WireGoldens/settings.jsonl"));
        var steps = lines.TakeWhile(l => !l.StartsWith("#! connect", StringComparison.Ordinal))
            .Where(l => l.StartsWith("> ", StringComparison.Ordinal) || l.StartsWith("< ", StringComparison.Ordinal))
            .Select(l => (sent: l[0] == '>', frame: (JsonObject)JsonNode.Parse(l[2..])!)).ToList();
        var documents = Fixtures.DocumentNames.Where(n => n.StartsWith("golden-", StringComparison.Ordinal)).ToList();

        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var changes = new List<ulong>();
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        var hello = await engine.ReceiveAsync();
        Matches(steps[0].frame, hello);
        await engine.SendAsync(Without(steps[1].frame, "v", "id"));
        await using var client = await connecting;
        client.SettingsChanged += changes.Add;

        var answered = 0;
        for (var i = 2; i < steps.Count; i++)
        {
            if (!steps[i].sent) continue;
            var request = steps[i].frame;
            Task<SettingsAnswer> sending = (string)request["type"]! switch
            {
                "settingsGet" => client.GetAsync(),
                "settingsSet" when request.ContainsKey("value") => client.SetAsync((string)request["field"]!, request["value"], default,
                                                                                    request["shown"], request["revision"]?.GetValue<ulong>()),
                "settingsSet" => Task.FromException<SettingsAnswer>(new InvalidOperationException("skip")),
                _ => client.ActionAsync(new SettingsActionRequest((string)request["field"]!, (string)request["action"]!,
                                                                 (string?)request["item"], request["value"], (string?)request["key"])),
            };
            if (!request.ContainsKey("value") && (string)request["type"]! == "settingsSet") continue;  // the client always sends a value
            var sent = await engine.ReceiveAsync();
            Matches(request, sent);
            // The engine's answer and the notification after it, as the golden has them.
            for (var j = i + 1; j < steps.Count && !steps[j].sent; j++)
            {
                var reply = (JsonObject)Without(steps[j].frame, "v", "id").DeepClone();
                if (reply.ContainsKey("re")) reply["re"] = sent["id"]!.GetValue<uint>();
                if (reply["document"] is JsonValue) reply["document"] = Fixtures.Answer(documents[answered])["document"]!.DeepClone();
                if (reply["problem"] is JsonObject problem && (string?)problem["message"] == "$any") problem["message"] = "refused";
                await engine.SendAsync(reply);
            }
            if ((string)steps[i + 1].frame["type"]! == "error")
            {
                var error = await Assert.ThrowsAsync<WireException>(() => sending);
                Assert.Equal((string)steps[i + 1].frame["code"]!, error.Code);
                continue;
            }
            var answer = await sending;
            var expected = steps[i + 1].frame;
            Assert.Equal(expected["revision"]!.GetValue<ulong>(), answer.Revision);
            Assert.Equal((string?)expected["problem"]?["code"], answer.Problem?.Code);
            Assert.Equal((string?)expected["problem"]?["field"], answer.Problem?.Field);
            Assert.NotEmpty(answer.Document.Sections);
            answered++;
        }
        Assert.Equal(documents.Count, answered);
        // Every settingsChanged of the golden's first connection, in order.
        var notified = steps.Where(step => !step.sent && (string?)step.frame["type"] == "settingsChanged")
            .Select(step => step.frame["revision"]!.GetValue<ulong>()).ToList();
        Assert.NotEmpty(notified);
        await WaitFor(() => changes.Count == notified.Count);
        Assert.Equal(notified, changes);
    }

    /// <summary>A list edited as the window showed it: <c>shown</c> goes with the value, and the revision when the
    /// request has one (§12.4); a request without them sends neither.</summary>
    [Fact]
    public async Task WhatTheWindowShowedGoesWithTheChange()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var document = (JsonObject)Fixtures.Answer("golden-01-settingsGet")["document"]!;
        var edit = client.SendAsync(new SettingsSetRequest("redaction.customWords", new JsonArray("Acme", "Mine"), shown: new JsonArray("Acme"), revision: 4));
        var frame = await engine.ReceiveAsync();
        Assert.Equal(["Acme"], ((JsonArray)frame["shown"]!).Select(v => (string?)v));
        Assert.Equal(4UL, frame["revision"]!.GetValue<ulong>());
        await engine.AnswerAsync(frame, 5, document);
        await edit;
        var plain = client.SendAsync(new SettingsSetRequest("maxTokens", JsonValue.Create(1500)));
        frame = await engine.ReceiveAsync();
        Assert.False(frame.ContainsKey("shown") || frame.ContainsKey("revision"));
        await engine.AnswerAsync(frame, 6, document, new JsonObject { ["code"] = "stale", ["field"] = "maxTokens", ["message"] = "changed" });
        var stale = await plain;
        Assert.True(stale.Problem!.IsStale);
    }

    /// <summary>A golden's <c>&gt;</c> line against what the client sent: the same keys and values, "$any" for any, the
    /// ids the client's own (counted from 1, hello first).</summary>
    static void Matches(JsonObject golden, JsonObject sent)
    {
        Assert.Equal(1, sent["v"]!.GetValue<int>());
        foreach (var (key, value) in golden)
        {
            if (key is "id" or "v") continue;
            // "$any": the client's own value, or none (a settings window has no TSF thread: no tid).
            if (value is JsonValue v && v.TryGetValue<string>(out var text) && text == "$any") continue;
            Assert.True(sent.ContainsKey(key), $"{key} missing from {sent.ToJsonString()}");
            Assert.True(JsonNode.DeepEquals(value, sent[key]), $"{key}: {sent[key]?.ToJsonString()} for {value?.ToJsonString()}");
        }
        var extra = sent.Select(p => p.Key).Except(golden.Select(p => p.Key)).Except(["v", "id"]).ToList();
        Assert.Empty(extra);
    }

    static JsonObject Without(JsonObject frame, params string[] keys)
    {
        var copy = (JsonObject)frame.DeepClone();
        foreach (var key in keys) copy.Remove(key);
        return copy;
    }

    static async Task WaitFor(Func<bool> condition)
    {
        for (var i = 0; i < 200 && !condition(); i++) await Task.Delay(10);
        Assert.True(condition());
    }

    [Fact]
    public async Task AnEngineThatDoesntGiveTheSettings()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync(settings: false);
        var error = await Assert.ThrowsAsync<WireException>(() => connecting);
        Assert.Equal("notGranted", error.Code);
    }

    [Fact]
    public async Task HelloSaysWhoItIs()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "0.6.6", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var hello = engine.Received[0];
        Assert.Equal("hello", (string?)hello["type"]);
        Assert.Equal(1, hello["id"]!.GetValue<int>());
        Assert.Equal("settings/0.6.6", (string?)hello["client"]);
        Assert.Equal(["settings"], ((JsonArray)hello["capabilities"]!).Select(c => (string?)c));
        Assert.Equal("win", (string?)hello["platform"]);
        Assert.Equal(Environment.ProcessId, hello["pid"]!.GetValue<int>());
        Assert.Equal("test", client.Engine);
    }

    /// <summary>Answers matched by <c>re</c>: a test that takes a while is answered after a change made meanwhile, and a
    /// notification in between goes to its event.</summary>
    [Fact]
    public async Task AnswersComeInAnyOrder()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var changes = new List<ulong>();
        client.SettingsChanged += changes.Add;
        var document = (JsonObject)Fixtures.Answer("golden-01-settingsGet")["document"]!;

        var test = client.ActionAsync(new SettingsActionRequest("provider.test", "test"));
        var testFrame = await engine.ReceiveAsync();
        var set = client.SetAsync("maxTokens", JsonValue.Create(1500));
        var setFrame = await engine.ReceiveAsync();
        await engine.AnswerAsync(setFrame, 2, document);
        await engine.SendAsync(new JsonObject { ["type"] = "settingsChanged", ["revision"] = 2 });
        await engine.AnswerAsync(testFrame, 3, document, message: "✓ 1.2 s: Hello.");
        Assert.Equal(2UL, (await set).Revision);
        var tested = await test;
        Assert.Equal(3UL, tested.Revision);
        Assert.Equal("✓ 1.2 s: Hello.", tested.Message);
        await WaitFor(() => changes.Count == 1);
        Assert.Equal("test", (string?)testFrame["action"]);
        Assert.Equal(1500, setFrame["value"]!.GetValue<int>());
    }

    /// <summary>Null is a value: sent as <c>"value":null</c>, never left out (which the engine refuses).</summary>
    [Fact]
    public async Task NullIsSentAsAValue()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var set = client.SetAsync("uiLanguage", null);
        var frame = await engine.ReceiveAsync();
        Assert.True(frame.ContainsKey("value"));
        Assert.Null(frame["value"]);
        await engine.AnswerAsync(frame, 1, (JsonObject)Fixtures.Answer("golden-01-settingsGet")["document"]!);
        await set;
    }

    /// <summary>A key goes in its frame once; the request never shows it, and an error frame comes back as an exception
    /// with the engine's code.</summary>
    [Fact]
    public async Task AKeyIsSentOnceAndShownNowhere()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var request = new SettingsActionRequest("anthropic.key", "setKey", key: "sk-test-secret-a1b2");
        Assert.DoesNotContain("sk-test", request.ToString());
        var saving = client.ActionAsync(request);
        var frame = await engine.ReceiveAsync();
        Assert.Equal("sk-test-secret-a1b2", (string?)frame["key"]);
        await engine.SendAsync(new JsonObject { ["re"] = frame["id"]!.GetValue<uint>(), ["type"] = "error", ["code"] = "notAllowed", ["message"] = "no" });
        var error = await Assert.ThrowsAsync<WireException>(() => saving);
        Assert.Equal("notAllowed", error.Code);
        Assert.DoesNotContain("sk-test", error.Message);
    }

    /// <summary>The engine going away (a broken pipe, bye) fails what waits, and says so once.</summary>
    [Fact]
    public async Task TheEngineGoingAway()
    {
        var pipe = new MemoryPipe();
        var engine = new FakeEngine(pipe.Engine);
        var connecting = SettingsClient.ConnectAsync(pipe.Client, "test", CancellationToken.None);
        await engine.WelcomeAsync();
        await using var client = await connecting;
        var closed = 0;
        client.Closed += _ => Interlocked.Increment(ref closed);
        var get = client.GetAsync();
        await engine.ReceiveAsync();
        await engine.SendAsync(new JsonObject { ["type"] = "bye", ["reason"] = "update", ["retryMs"] = 500 });
        var error = await Assert.ThrowsAsync<WireException>(() => get);
        Assert.Equal("closed", error.Code);
        await WaitFor(() => closed == 1);
        await Assert.ThrowsAsync<WireException>(() => client.GetAsync());
    }

    [Fact]
    public void Frames()
    {
        var frame = WireFrame.Encode(new JsonObject { ["type"] = "settingsGet", ["text"] = "中文" });
        Assert.Equal((uint)(frame.Length - 4), BitConverter.ToUInt32(frame, 0));
        Assert.Equal("中文", (string?)WireFrame.Decode(frame)["text"]);
        var wrong = frame.ToArray();
        wrong[0]++;
        Assert.Equal("badFrame", Assert.Throws<WireException>(() => WireFrame.Decode(wrong)).Code);
        Assert.Equal("badFrame", Assert.Throws<WireException>(() => WireFrame.Decode([1, 0, 0, 0, (byte)'['])).Code);
        var big = new JsonObject { ["text"] = new string('x', WireFrame.MaxClientBody) };
        Assert.Equal("tooLarge", Assert.Throws<WireException>(() => WireFrame.Encode(big)).Code);
        Assert.Equal("{\"a\":1}", Encoding.UTF8.GetString(WireFrame.Encode(new JsonObject { ["a"] = 1 })[4..]));
    }
}
