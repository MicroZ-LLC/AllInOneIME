using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Presentation;
using AllInOneIME.Settings.Wire;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace AllInOneIME.Settings;

/// <summary>
/// One section of the document drawn: its title, the document's errors, a card per field, its footer. A newer document
/// updates the cards in place where a field is drawn the same way (so that the focus, a text being typed, an open list
/// stay as they are), and draws anew only the cards whose field changed shape; the focus goes back where it was.
/// </summary>
public sealed class SectionPage
{
    readonly MainWindow window;
    readonly SettingsConnection connection;
    readonly TextBlock header = new() { Margin = new Thickness(0, 0, 0, 12), TextWrapping = TextWrapping.Wrap };
    readonly InfoBar documentBar = new() { IsClosable = false, Severity = InfoBarSeverity.Error, Margin = new Thickness(0, 0, 0, 8) };
    readonly InfoBar answerBar = new() { IsClosable = true, Margin = new Thickness(0, 0, 0, 8) };
    readonly TextBlock footer = new() { Margin = new Thickness(4, 12, 4, 0), TextWrapping = TextWrapping.Wrap };
    /// <summary>The page's controls, all of them disabled while there is no connection (the keyboard too).</summary>
    readonly ContentControl host = new()
    {
        IsTabStop = false, HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Top,
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };
    Dictionary<string, FieldCard> cards = [];
    string? shown;
    bool enabled;

    public SectionPage(MainWindow window, SettingsConnection connection)
    {
        this.window = window;
        this.connection = connection;
        header.Style = Styles.Get("TitleTextBlockStyle");
        AutomationProperties.SetHeadingLevel(header, AutomationHeadingLevel.Level1);
        footer.Style = Styles.Get("SecondaryTextStyle");
        AutomationProperties.SetLiveSetting(answerBar, AutomationLiveSetting.Assertive);
        AutomationProperties.SetLiveSetting(documentBar, AutomationLiveSetting.Assertive);
        Panel.Padding = new Thickness(32, 20, 32, 32);
        Panel.MaxWidth = 1000;
        Panel.HorizontalAlignment = HorizontalAlignment.Stretch;
        host.Content = Panel;
        Root.Content = host;
        Root.HorizontalScrollMode = ScrollMode.Disabled;
        Root.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
    }

    public ScrollViewer Root { get; } = new();
    public StackPanel Panel { get; } = new() { Spacing = 4 };

    /// <summary>The page drawn into a file (the screenshots): its own background, as the window's Mica isn't in it.</summary>
    public void UseSolidBackground() => Panel.Style = Styles.Get("SolidPanelStyle");
    public XamlRoot? XamlRoot => window.Content.XamlRoot;
    public ElementTheme Theme => window.RootElement.ActualTheme;
    public IntPtr WindowHandle => WinRT.Interop.WindowNative.GetWindowHandle(window);

    /// <summary>The items lists' open entries (by list and item), kept while the document changes.</summary>
    public Dictionary<string, bool> Expanded { get; } = [];
    /// <summary>The fields whose action is under way (a test), kept while their cards are drawn anew.</summary>
    public HashSet<string> Busy { get; } = [];
    /// <summary>Every items list's entries open (the screenshots).</summary>
    public bool ExpandAll { get; set; }

    /// <summary>Connected or not: without a connection nothing can be changed, by the mouse or the keyboard (a key
    /// pasted then would go nowhere), and the page is dimmed.</summary>
    public void SetEnabled(bool on)
    {
        enabled = on;
        host.IsEnabled = on;
        Panel.Opacity = on ? 1 : 0.6;
    }

    public bool IsEnabled => enabled;

    public void ShowSection(SettingsDocument? document, string? id, bool keepScroll, SettingsAnswer? answer = null)
    {
        if (document is null) return;
        var section = document.Sections.FirstOrDefault(s => s.Id == id) ?? document.Sections.FirstOrDefault();
        if (section is null) return;
        if (section.Id != shown)
        {
            cards.Clear();
            Panel.Children.Clear();
            answerBar.IsOpen = false;
            shown = section.Id;
            keepScroll = false;
        }
        var focus = FocusedAutomationId();
        var context = new CardContext(this, document, new WindowText(document));

        header.Text = section.Title;
        var error = document.LoadError ?? document.SaveError;
        documentBar.Message = error ?? "";
        documentBar.IsOpen = error is not null;
        AutomationProperties.SetName(documentBar, error ?? "");

        var desired = new List<UIElement> { header, documentBar, answerBar };
        var next = new Dictionary<string, FieldCard>();
        foreach (var field in section.Fields)
        {
            if (!cards.TryGetValue(field.Id, out var card) || !card.TryUpdate(field, context)) card = FieldCard.Create(field, context);
            next[field.Id] = card;
            desired.Add(card.Root);
        }
        footer.Text = section.Footer ?? "";
        footer.Visibility = section.Footer is null ? Visibility.Collapsed : Visibility.Visible;
        desired.Add(footer);
        cards = next;
        Reconcile(Panel.Children, desired);
        if (!keepScroll) Root.ChangeView(null, 0, null, disableAnimation: true);
        if (focus is not null) RestoreFocus(focus);
    }

    /// <summary>Makes <paramref name="children"/> the <paramref name="desired"/> elements, moving none that stays (a
    /// focused control keeps the focus).</summary>
    static void Reconcile(UIElementCollection children, List<UIElement> desired)
    {
        var keep = desired.ToHashSet();
        for (var i = children.Count - 1; i >= 0; i--)
        {
            if (!keep.Contains(children[i])) children.RemoveAt(i);
        }
        for (var i = 0; i < desired.Count; i++)
        {
            if (i < children.Count && ReferenceEquals(children[i], desired[i])) continue;
            var at = children.IndexOf(desired[i]);
            if (at >= 0) children.RemoveAt(at);
            children.Insert(i, desired[i]);
        }
        while (children.Count > desired.Count) children.RemoveAt(children.Count - 1);
    }

    /// <summary>The card of the field <paramref name="id"/>, wherever it is (an item's own fields too).</summary>
    public FieldCard? Find(string? id) => id is null ? null : cards.Values.Select(c => c.Find(id)).FirstOrDefault(c => c is not null);

    /// <summary>Sends what the user did; the answer's document is drawn (by the connection), then what it refused or
    /// said is shown at the field it is about.</summary>
    public async Task<SettingsAnswer?> SendAsync(SettingsRequest request, FieldCard from)
    {
        if (!enabled) return null;
        var takesAWhile = request is SettingsActionRequest { TakesAWhile: true };
        if (takesAWhile)
        {
            Busy.Add(request.Field);
            from.SetBusy(true);
        }
        try
        {
            var answer = await connection.SendAsync(request);
            if (answer is null) return null;
            var card = Find(request.Field) ?? from;
            if (answer.Problem is { IsCancelled: true } stopped)
            {
                // Stopped (Cancel, or the same action again): said as its outcome, not as an error.
                card.ShowProblem(null);
                card.ShowOutcome(stopped.Message);
            }
            else if (answer.Problem is { } problem)
            {
                // Refused; stale: the settings changed meanwhile, the document drawn is as they are now, and the user
                // makes the change again on it.
                var at = Find(problem.Field) ?? card;
                at.ShowProblem(problem.Message);
                if (!at.Root.IsLoaded || at.Root.Visibility != Visibility.Visible) ShowAnswer(InfoBarSeverity.Error, problem.Message);
            }
            else
            {
                card.ShowProblem(null);
                answerBar.IsOpen = false;
            }
            if (answer.Message is { } message) card.ShowOutcome(message);
            return answer;
        }
        catch (Exception error) when (error is WireException or InvalidOperationException or FormatException or System.Text.Json.JsonException)
        {
            // The connection went away (the window says so), the frame was refused or its answer can't be read: the
            // field shows what it was. (A handler of a click is async void: nothing may escape it.)
            ShowSection(connection.Document, shown, keepScroll: true);
            return null;
        }
        finally
        {
            if (takesAWhile)
            {
                Busy.Remove(request.Field);
                (Find(request.Field) ?? from).SetBusy(false);
            }
        }
    }

    void ShowAnswer(InfoBarSeverity severity, string message)
    {
        answerBar.Severity = severity;
        answerBar.Message = message;
        AutomationProperties.SetName(answerBar, message);
        answerBar.IsOpen = true;
    }

    /// <summary>A text typed and not committed yet (the window is closing).</summary>
    public bool HasPendingEdit => cards.Values.Any(c => c.HasPendingEdit);

    public async Task CommitPendingEditAsync()
    {
        foreach (var card in cards.Values.Where(c => c.HasPendingEdit).ToList()) await card.CommitAsync();
    }

    public void DropPendingEdit()
    {
        foreach (var card in cards.Values) card.DropEdit();
    }

    // MARK: Focus

    string? FocusedAutomationId()
    {
        if (XamlRoot is null) return null;
        for (var element = FocusManager.GetFocusedElement(XamlRoot) as DependencyObject; element is not null;
             element = VisualTreeHelper.GetParent(element))
        {
            if (element is FrameworkElement framework && AutomationProperties.GetAutomationId(framework) is { Length: > 0 } automationId)
            {
                return automationId;
            }
        }
        return null;
    }

    void RestoreFocus(string automationId)
    {
        window.DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            if (FocusedAutomationId() == automationId) return;
            if (FindElement(Panel, automationId) is Control control) control.Focus(FocusState.Programmatic);
        });
    }

    static DependencyObject? FindElement(DependencyObject parent, string automationId)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is FrameworkElement element && AutomationProperties.GetAutomationId(element) == automationId) return child;
            if (FindElement(child, automationId) is { } found) return found;
        }
        return null;
    }
}

/// <summary>What a card draws with: the page (to send and to keep state), the document, the window's words.</summary>
public sealed record CardContext(SectionPage Page, SettingsDocument Document, WindowText Text);

/// <summary>An icon for the sections the core has; any other gets a generic one.</summary>
static class SectionIcons
{
    public static IconElement For(string id) => new FontIcon
    {
        Glyph = id switch
        {
            "general" => "",
            "input" => "",
            "writing" => "",
            "provider" => "",
            "request" => "",
            "privacy" => "",
            "agent" => "",
            "apps" => "",
            "plugins" => "",
            "extensions" => "",
            "search" => "",
            "notes" => "",
            "commands" => "",
            "advanced" => "",
            _ => "",
        },
    };
}
