using System.Globalization;
using AllInOneIME.Settings.Document;

namespace AllInOneIME.Settings.Presentation;

/// <summary>
/// The words of the window's own controls: the document's (<c>strings</c>, in the interface language, §12.3), else
/// English. Before there is a document (connecting, the engine not there), the few messages the window says on its own,
/// in Windows' display language among the nine the core has.
/// </summary>
public sealed class WindowText(SettingsDocument? document)
{
    static readonly Dictionary<string, string> English = new()
    {
        ["window.title"] = "AllInOneIME Settings",
        ["action.setKey"] = "Save", ["action.removeKey"] = "Remove…", ["action.test"] = "Test", ["action.browse"] = "Open the Library",
        ["action.install"] = "Install", ["action.remove"] = "Remove", ["action.save"] = "New…", ["action.save.item"] = "Edit…",
        ["action.delete"] = "Delete…", ["action.add"] = "Add", ["action.hide"] = "Hide", ["action.show"] = "Show",
        ["confirm.removeKey"] = "Remove “{name}”?", ["confirm.delete"] = "Delete “{name}”?", ["confirm.removeItem"] = "Remove “{name}”?",
        ["save"] = "Save", ["cancel"] = "Cancel", ["choose"] = "Choose…", ["moveUp"] = "Move up", ["moveDown"] = "Move down",
        ["remove"] = "Remove", ["add"] = "Add…", ["paste"] = "Paste it", ["working"] = "Working…",
    };

    /// <summary>A word of the window's: the document's, else English, else the name itself.</summary>
    public string this[string name] =>
        document?.Strings.GetValueOrDefault(name) is { Length: > 0 } word ? word : English.GetValueOrDefault(name, name);

    /// <summary>The button of an action: an item's (<c>action.save.item</c>: "Edit…") where it differs from the field's.</summary>
    public string Action(string action, bool onItem = false) =>
        onItem && document?.Strings.ContainsKey($"action.{action}.item") == true || onItem && English.ContainsKey($"action.{action}.item")
            ? this[$"action.{action}.item"] : this[$"action.{action}"];

    /// <summary>The question an action that deletes asks first, about <paramref name="name"/>; null for one that asks
    /// nothing.</summary>
    public string? Confirmation(string action, bool onItem, string name)
    {
        var key = action switch
        {
            "removeKey" => "confirm.removeKey",
            "delete" => "confirm.delete",
            "remove" when onItem => "confirm.removeItem",
            _ => null,
        };
        return key is null ? null : this[key].Replace("{name}", name);
    }

    // MARK: Before there is a document

    /// <summary>What the window says on its own, by Windows' display language.</summary>
    public static string Own(OwnText text, CultureInfo? culture = null)
    {
        var language = Language(culture ?? CultureInfo.CurrentUICulture);
        return Own(text, language);
    }

    public static string Own(OwnText text, string language) =>
        OwnTable.TryGetValue(language, out var table) && table.TryGetValue(text, out var word) ? word : OwnTable["en"][text];

    /// <summary>One of the nine: zh-Hans, zh-Hant, en, de, es, fr, ja, ko, pt-BR (English for the others).</summary>
    public static string Language(CultureInfo culture)
    {
        var name = culture.Name;
        if (name.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
        {
            return name.Contains("Hant", StringComparison.OrdinalIgnoreCase) || name.EndsWith("TW", StringComparison.OrdinalIgnoreCase)
                || name.EndsWith("HK", StringComparison.OrdinalIgnoreCase) || name.EndsWith("MO", StringComparison.OrdinalIgnoreCase)
                ? "zh-Hant" : "zh-Hans";
        }
        if (name.StartsWith("pt", StringComparison.OrdinalIgnoreCase)) return "pt-BR";
        var two = culture.TwoLetterISOLanguageName;
        return two is "de" or "es" or "fr" or "ja" or "ko" ? two : "en";
    }

    static readonly Dictionary<string, Dictionary<OwnText, string>> OwnTable = new()
    {
        ["en"] = new()
        {
            [OwnText.Title] = "AllInOneIME Settings",
            [OwnText.Connecting] = "Connecting to AllInOneIME…",
            [OwnText.Reconnecting] = "AllInOneIME restarted: connecting again…",
            [OwnText.NotInstalled] = "AllInOneIME isn't running, and it isn't installed on this PC, so it can't be started.",
            [OwnText.CouldNotStart] = "AllInOneIME isn't running and couldn't be started.",
            [OwnText.NoAnswer] = "AllInOneIME doesn't answer.",
            [OwnText.NotAllowed] = "AllInOneIME doesn't let this window change the settings.",
            [OwnText.TryAgain] = "Try Again",
        },
        ["zh-Hans"] = new()
        {
            [OwnText.Title] = "AllInOneIME 设置",
            [OwnText.Connecting] = "正在连接 AllInOneIME…",
            [OwnText.Reconnecting] = "AllInOneIME 重新启动了，正在重新连接…",
            [OwnText.NotInstalled] = "AllInOneIME 没有在运行，这台电脑上也没有安装它，所以无法启动。",
            [OwnText.CouldNotStart] = "AllInOneIME 没有在运行，也没能启动。",
            [OwnText.NoAnswer] = "AllInOneIME 没有响应。",
            [OwnText.NotAllowed] = "AllInOneIME 不允许这个窗口修改设置。",
            [OwnText.TryAgain] = "重试",
        },
        ["zh-Hant"] = new()
        {
            [OwnText.Title] = "AllInOneIME 設定",
            [OwnText.Connecting] = "正在連線 AllInOneIME…",
            [OwnText.Reconnecting] = "AllInOneIME 重新啟動了，正在重新連線…",
            [OwnText.NotInstalled] = "AllInOneIME 沒有在執行，這台電腦上也沒有安裝它，所以無法啟動。",
            [OwnText.CouldNotStart] = "AllInOneIME 沒有在執行，也沒能啟動。",
            [OwnText.NoAnswer] = "AllInOneIME 沒有回應。",
            [OwnText.NotAllowed] = "AllInOneIME 不允許這個視窗修改設定。",
            [OwnText.TryAgain] = "重試",
        },
        ["de"] = new()
        {
            [OwnText.Title] = "AllInOneIME-Einstellungen",
            [OwnText.Connecting] = "Verbindung mit AllInOneIME wird hergestellt…",
            [OwnText.Reconnecting] = "AllInOneIME wurde neu gestartet: neue Verbindung…",
            [OwnText.NotInstalled] = "AllInOneIME läuft nicht und ist auf diesem PC nicht installiert, daher kann es nicht gestartet werden.",
            [OwnText.CouldNotStart] = "AllInOneIME läuft nicht und konnte nicht gestartet werden.",
            [OwnText.NoAnswer] = "AllInOneIME antwortet nicht.",
            [OwnText.NotAllowed] = "AllInOneIME lässt dieses Fenster die Einstellungen nicht ändern.",
            [OwnText.TryAgain] = "Erneut versuchen",
        },
        ["es"] = new()
        {
            [OwnText.Title] = "Ajustes de AllInOneIME",
            [OwnText.Connecting] = "Conectando con AllInOneIME…",
            [OwnText.Reconnecting] = "AllInOneIME se reinició: conectando de nuevo…",
            [OwnText.NotInstalled] = "AllInOneIME no se está ejecutando y no está instalado en este PC, así que no se puede iniciar.",
            [OwnText.CouldNotStart] = "AllInOneIME no se está ejecutando y no se pudo iniciar.",
            [OwnText.NoAnswer] = "AllInOneIME no responde.",
            [OwnText.NotAllowed] = "AllInOneIME no permite que esta ventana cambie los ajustes.",
            [OwnText.TryAgain] = "Reintentar",
        },
        ["fr"] = new()
        {
            [OwnText.Title] = "Réglages d’AllInOneIME",
            [OwnText.Connecting] = "Connexion à AllInOneIME…",
            [OwnText.Reconnecting] = "AllInOneIME a redémarré : nouvelle connexion…",
            [OwnText.NotInstalled] = "AllInOneIME n’est pas lancé et n’est pas installé sur ce PC : impossible de le démarrer.",
            [OwnText.CouldNotStart] = "AllInOneIME n’est pas lancé et n’a pas pu démarrer.",
            [OwnText.NoAnswer] = "AllInOneIME ne répond pas.",
            [OwnText.NotAllowed] = "AllInOneIME ne laisse pas cette fenêtre modifier les réglages.",
            [OwnText.TryAgain] = "Réessayer",
        },
        ["ja"] = new()
        {
            [OwnText.Title] = "AllInOneIME の設定",
            [OwnText.Connecting] = "AllInOneIME に接続しています…",
            [OwnText.Reconnecting] = "AllInOneIME が再起動しました。再接続しています…",
            [OwnText.NotInstalled] = "AllInOneIME は実行されておらず、この PC にインストールされていないため、起動できません。",
            [OwnText.CouldNotStart] = "AllInOneIME は実行されておらず、起動できませんでした。",
            [OwnText.NoAnswer] = "AllInOneIME が応答しません。",
            [OwnText.NotAllowed] = "AllInOneIME はこのウインドウからの設定変更を許可していません。",
            [OwnText.TryAgain] = "再試行",
        },
        ["ko"] = new()
        {
            [OwnText.Title] = "AllInOneIME 설정",
            [OwnText.Connecting] = "AllInOneIME에 연결하는 중…",
            [OwnText.Reconnecting] = "AllInOneIME가 다시 시작되었습니다. 다시 연결하는 중…",
            [OwnText.NotInstalled] = "AllInOneIME가 실행 중이 아니며 이 PC에 설치되어 있지 않아 시작할 수 없습니다.",
            [OwnText.CouldNotStart] = "AllInOneIME가 실행 중이 아니며 시작할 수 없었습니다.",
            [OwnText.NoAnswer] = "AllInOneIME가 응답하지 않습니다.",
            [OwnText.NotAllowed] = "AllInOneIME가 이 창에서 설정을 변경하도록 허용하지 않습니다.",
            [OwnText.TryAgain] = "다시 시도",
        },
        ["pt-BR"] = new()
        {
            [OwnText.Title] = "Ajustes do AllInOneIME",
            [OwnText.Connecting] = "Conectando ao AllInOneIME…",
            [OwnText.Reconnecting] = "O AllInOneIME reiniciou: conectando de novo…",
            [OwnText.NotInstalled] = "O AllInOneIME não está em execução e não está instalado neste PC, então não pode ser iniciado.",
            [OwnText.CouldNotStart] = "O AllInOneIME não está em execução e não pôde ser iniciado.",
            [OwnText.NoAnswer] = "O AllInOneIME não responde.",
            [OwnText.NotAllowed] = "O AllInOneIME não permite que esta janela altere os ajustes.",
            [OwnText.TryAgain] = "Tentar de novo",
        },
    };
}

/// <summary>What the window says before it has a document.</summary>
public enum OwnText
{
    Title,
    Connecting,
    Reconnecting,
    NotInstalled,
    CouldNotStart,
    NoAnswer,
    NotAllowed,
    TryAgain,
}
