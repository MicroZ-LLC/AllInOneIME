using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AllInOneIME.Settings.Wire;

/// <summary>
/// One frame of wire protocol v1 (§2.2): a u32 little-endian body length, then that many bytes of UTF-8 JSON, one
/// object. A settings window writes at most 1 MiB once it has the settings (a DLL 64 KiB), and reads at most 1 MiB.
/// </summary>
public static class WireFrame
{
    public const int Version = 1;
    /// <summary>What a settings window may write (§2.2): a list as long as the settings keep (2,000 English words of up
    /// to 40 characters) with the list it showed, escaped as this client escapes them. Its <c>hello</c> is far
    /// smaller than a DLL's limit, 64 KiB, which holds until the engine grants the settings.</summary>
    public const int MaxClientBody = 1024 * 1024;
    public const int MaxEngineBody = 1024 * 1024;

    static readonly JsonSerializerOptions Compact = new() { WriteIndented = false };

    /// <summary>The frame for <paramref name="body"/>: its length, then its JSON.</summary>
    public static byte[] Encode(JsonObject body)
    {
        var json = Encoding.UTF8.GetBytes(body.ToJsonString(Compact));
        if (json.Length > MaxClientBody) throw new WireException("tooLarge", $"a frame of {json.Length} bytes");
        var frame = new byte[json.Length + 4];
        BinaryPrimitives.WriteUInt32LittleEndian(frame, (uint)json.Length);
        json.CopyTo(frame, 4);
        Array.Clear(json);
        return frame;
    }

    /// <summary>The object a whole pipe message holds; the prefix must be the message's size less 4.</summary>
    public static JsonObject Decode(ReadOnlySpan<byte> message)
    {
        if (message.Length < 4) throw new WireException("badFrame", "a message shorter than its prefix");
        var length = BinaryPrimitives.ReadUInt32LittleEndian(message);
        if (length != message.Length - 4) throw new WireException("badFrame", $"a prefix of {length} for {message.Length - 4} bytes");
        if (length > MaxEngineBody) throw new WireException("tooLarge", $"a frame of {length} bytes");
        try
        {
            return JsonNode.Parse(message[4..], documentOptions: new JsonDocumentOptions { MaxDepth = 64 }) as JsonObject
                ?? throw new WireException("badFrame", "a frame that isn't an object");
        }
        catch (JsonException)
        {
            throw new WireException("badFrame", "a frame that isn't JSON");
        }
    }
}

/// <summary>What went wrong on the wire: an engine's <c>error</c> frame (its <c>code</c>), or the frame or pipe itself.</summary>
public sealed class WireException(string code, string message) : Exception(message)
{
    /// <summary><c>badFrame</c>, <c>notAllowed</c>, <c>unknownType</c>, <c>badMessage</c>, … (§3), or the client's own:
    /// <c>closed</c>, <c>timeout</c>, <c>notGranted</c>, <c>serverCheck</c>.</summary>
    public string Code { get; } = code;
}
