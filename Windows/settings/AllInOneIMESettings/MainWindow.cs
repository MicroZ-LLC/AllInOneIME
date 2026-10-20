using System.Reflection;
using System.Runtime.InteropServices;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Presentation;
using AllInOneIME.Settings.Wire;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace AllInOneIME.Settings;

/// <summary>
/// The window: the document's sections in a navigation pane, the one picked drawn as cards of fields (<see
/// cref="SectionPage"/>), and a bar that says when the engine can't be reached. Everything it shows is the document's;
/// a change goes to the engine and the window draws the answer.
/// </summary>
public sealed class MainWindow : Window
{
    readonly AppOptions options;
    readonly SettingsConnection connection;
    readonly Grid root = new();
    readonly InfoBar bar = new() { IsClosable = false, IsOpen = false, Margin = new Thickness(12, 8, 12, 0) };
    readonly NavigationView navigation = new()
    {
        PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
        IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
        IsSettingsVisible = false,
        IsPaneToggleButtonVisible = true,
        OpenPaneLength = 280,
    };
    readonly SectionPage page;
    string? sectionId;
    bool selecting;

    public MainWindow(AppOptions options, string pipe)
    {
        this.options = options;
        sectionId = options.Section;
        Title = WindowText.Own(OwnText.Title);
        var icon = Path.Combine(AppContext.BaseDirectory, "AllInOneIME.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        var (width, height) = options.Size ?? (1040, 760);
        var scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(width * scale), (int)(height * scale)));

        if (options.Theme is "dark") root.RequestedTheme = ElementTheme.Dark;
        if (options.Theme is "light") root.RequestedTheme = ElementTheme.Light;
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(navigation, 1);
        root.Children.Add(bar);
        root.Children.Add(navigation);
        Content = root;
        // Mica behind the window, as Windows' own Settings; drawn into a file, the page's solid background instead.
        if (options.Screenshots is null) SystemBackdrop = new MicaBackdrop();
        else root.Style = Styles.Get("SolidPageStyle");
        root.ActualThemeChanged += (_, _) => FollowTheme();
        FollowTheme();

        var connector = new EngineConnector
        {
            Pipe = pipe,
            // A test's engine (--engine) on a test's pipe; the installed one only on the user's own pipe.
            FindEngine = options.Engine is { } engine ? () => (engine, options.EngineArguments)
                : options.Pipe is null ? EngineConnector.InstalledEngine : () => null,
        };
        connection = new SettingsConnection(async cancellation => await connector.ConnectAsync(cancellation),
                                            action => DispatcherQueue.TryEnqueue(() => action()),
                                            typeof(MainWindow).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0");
        connection.StateChanged += ShowState;
        connection.DocumentChanged += Show;
        page = new SectionPage(this, connection);
        if (options.Screenshots is not null) page.UseSolidBackground();
        navigation.Content = page.Root;
        navigation.SelectionChanged += (_, args) =>
        {
            if (selecting || args.SelectedItem is not NavigationViewItem item) return;
            sectionId = item.Tag as string;
            page.ShowSection(connection.Document, sectionId, keepScroll: false);
        };
        AppWindow.Closing += Closing;
        ShowState();
        _ = connection.StartAsync();
    }

    /// <summary>The window, brought to the front (a second start of the app asked for it).</summary>
    public void BringForward()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter) presenter.Restore();
        AppWindow.Show();
        Activate();
        SetForegroundWindow(WinRT.Interop.WindowNative.GetWindowHandle(this));
    }

    /// <summary>A text being typed is committed before the window goes.</summary>
    async void Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (!page.HasPendingEdit) return;
        args.Cancel = true;
        await page.CommitPendingEditAsync();
        page.DropPendingEdit();
        Close();
    }

    void ShowState()
    {
        var text = new WindowText(connection.Document);
        switch (connection.State)
        {
            case ConnectionState.Connecting:
                ShowBar(InfoBarSeverity.Informational, WindowText.Own(OwnText.Connecting), retry: false);
                break;
            case ConnectionState.Reconnecting:
                ShowBar(InfoBarSeverity.Warning, WindowText.Own(OwnText.Reconnecting), retry: false);
                break;
            case ConnectionState.Unavailable:
                var why = connection.Problem switch
                {
                    EngineUnavailableException { Problem: EngineProblem.NotInstalled } => OwnText.NotInstalled,
                    EngineUnavailableException { Problem: EngineProblem.CouldNotStart } => OwnText.CouldNotStart,
                    WireException { Code: "notGranted" or "notAllowed" or "serverCheck" } => OwnText.NotAllowed,
                    _ => OwnText.NoAnswer,
                };
                ShowBar(InfoBarSeverity.Error, WindowText.Own(why), retry: true);
                if (options.Screenshots is not null) Application.Current.Exit();
                break;
            case ConnectionState.Connected:
                bar.IsOpen = false;
                Title = text["window.title"];
                break;
        }
        page.SetEnabled(connection.State == ConnectionState.Connected);
    }

    void ShowBar(InfoBarSeverity severity, string message, bool retry)
    {
        bar.Severity = severity;
        bar.Message = message;
        AutomationProperties.SetName(bar, message);
        AutomationProperties.SetLiveSetting(bar, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Assertive);
        if (retry)
        {
            var button = new Button { Content = WindowText.Own(OwnText.TryAgain) };
            button.Click += (_, _) => _ = connection.StartAsync();
            bar.ActionButton = button;
        }
        else
        {
            bar.ActionButton = null;
        }
        bar.IsOpen = true;
    }

    /// <summary>A newer document: the sections in the pane (the one shown kept, else the first), the page drawn again.</summary>
    void Show(SettingsAnswer? answer)
    {
        var document = connection.Document;
        if (document is null) return;
        Title = new WindowText(document)["window.title"];
        selecting = true;
        try
        {
            var items = navigation.MenuItems.OfType<NavigationViewItem>().ToList();
            var same = items.Count == document.Sections.Count
                && items.Zip(document.Sections).All(pair => (string?)pair.First.Tag == pair.Second.Id);
            if (!same)
            {
                navigation.MenuItems.Clear();
                foreach (var section in document.Sections)
                {
                    var item = new NavigationViewItem { Content = section.Title, Tag = section.Id, Icon = SectionIcons.For(section.Id) };
                    AutomationProperties.SetAutomationId(item, "section:" + section.Id);
                    navigation.MenuItems.Add(item);
                }
            }
            else
            {
                foreach (var (item, section) in items.Zip(document.Sections)) item.Content = section.Title;
            }
            if (document.Sections.All(s => s.Id != sectionId)) sectionId = document.Sections.FirstOrDefault()?.Id;
            navigation.SelectedItem = navigation.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string?)i.Tag == sectionId);
        }
        finally
        {
            selecting = false;
        }
        page.ShowSection(document, sectionId, keepScroll: true, answer);
        if (options.Screenshots is { } folder && answer is not null && !shooting)
        {
            shooting = true;
            _ = Screenshots.TakeAsync(this, folder, options.Theme ?? "light");
        }
    }

    bool shooting;

    /// <summary>The sections, for the screenshots.</summary>
    internal IReadOnlyList<Section> Sections => connection.Document?.Sections ?? [];

    /// <summary>Shows the section <paramref name="id"/>, its items' own fields open (for the screenshots).</summary>
    internal void SelectSection(string id, bool expandAll)
    {
        sectionId = id;
        page.ExpandAll = expandAll;
        selecting = true;
        navigation.SelectedItem = navigation.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string?)i.Tag == id);
        selecting = false;
        page.ShowSection(connection.Document, id, keepScroll: false);
    }

    internal FrameworkElement RootElement => root;
    internal FrameworkElement PageElement => page.Panel;

    /// <summary>The title bar's buttons in the window's theme (Windows' own, or the one a test forced).</summary>
    void FollowTheme()
    {
        if (!AppWindowTitleBar.IsCustomizationSupported()) return;
        AppWindow.TitleBar.PreferredTheme = root.ActualTheme == ElementTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light;
    }

    [DllImport("user32.dll")]
    static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    static extern bool SetForegroundWindow(IntPtr window);
}
