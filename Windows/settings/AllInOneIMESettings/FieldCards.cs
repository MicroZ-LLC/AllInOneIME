using System.Text.Json.Nodes;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Presentation;
using AllInOneIME.Settings.Wire;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace AllInOneIME.Settings;

/// <summary>
/// A field drawn as a card: its label, help, state and what was refused, and the control its kind takes
/// (<see cref="FieldPresenter.ControlFor"/>). The control's accessible name is the label and its help text the help;
/// its automation id is the field's id (a control of its own within the card adds "/" and what it does).
/// </summary>
public abstract class FieldCard
{
    static readonly string[] Volatile = ["value", "label", "help", "status", "isSet", "text", "placeholder"];

    readonly TextBlock label = new() { TextWrapping = TextWrapping.Wrap };
    readonly TextBlock help = new() { TextWrapping = TextWrapping.Wrap };
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
    readonly TextBlock problem = new() { TextWrapping = TextWrapping.Wrap };
    string? outcome;

    protected FieldCard(Field field, CardContext context)
    {
        Field = field;
        Context = context;
        label.Style = Styles.Get("BodyTextBlockStyle");
        help.Style = status.Style = Styles.Get("SecondaryTextStyle");
        problem.Style = Styles.Get("ProblemTextStyle");
        AutomationProperties.SetLiveSetting(problem, AutomationLiveSetting.Assertive);
        AutomationProperties.SetLiveSetting(status, AutomationLiveSetting.Polite);
    }

    public Field Field { get; private set; }
    protected CardContext Context { get; private set; }
    public FrameworkElement Root { get; private set; } = null!;
    /// <summary>The grid the card's texts and control are in.</summary>
    protected Grid Layout { get; } = new() { ColumnSpacing = 16, RowSpacing = 8 };
    protected bool Enabled => FieldPresenter.IsEnabled(Field, Context.Document);

    public static FieldCard Create(Field field, CardContext context) => FieldPresenter.ControlFor(field) switch
    {
        FieldControl.Toggle => new ToggleCard(field, context),
        FieldControl.NumberBox => new NumberCard(field, context),
        FieldControl.Slider or FieldControl.OptionalSlider => new SliderCard(field, context),
        FieldControl.TextBox or FieldControl.TextWithSuggestions or FieldControl.Words => new TextCard(field, context),
        FieldControl.ComboBox => new ComboCard(field, context),
        FieldControl.CheckList => new CheckListCard(field, context),
        FieldControl.OrderedList => new OrderedListCard(field, context),
        FieldControl.Secret => new SecretCard(field, context),
        FieldControl.Items => new ItemsCard(field, context),
        FieldControl.Button => new ButtonCard(field, context),
        _ => new InfoCard(field, context),
    };

    /// <summary>The same field drawn the same way, updated in place: true; another shape: false (drawn anew).</summary>
    public virtual bool TryUpdate(Field field, CardContext context)
    {
        if (FieldPresenter.ControlFor(field) != FieldPresenter.ControlFor(Field) || !SameShape(Field, field)) return false;
        var old = Field;
        Field = field;
        Context = context;
        ShowTexts();
        Update(old);
        return true;
    }

    /// <summary>Two versions of a field differ only in what a card updates in place.</summary>
    protected static bool SameShape(Field a, Field b)
    {
        var x = (JsonObject)a.Json.DeepClone();
        var y = (JsonObject)b.Json.DeepClone();
        foreach (var key in Volatile)
        {
            x.Remove(key);
            y.Remove(key);
        }
        return JsonNode.DeepEquals(x, y);
    }

    /// <summary>The control shows the field's value as it is now.</summary>
    protected virtual void Update(Field old) { }

    /// <summary>This card, or one of its own (an item's field), for the field <paramref name="id"/>.</summary>
    public virtual FieldCard? Find(string id) => Field.Id == id ? this : null;

    /// <summary>What a change of it was refused for (null: nothing now).</summary>
    public void ShowProblem(string? message)
    {
        problem.Text = message ?? "";
        problem.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>What its action said (a test's outcome), until the document says otherwise.</summary>
    public virtual void ShowOutcome(string message)
    {
        outcome = message;
        ShowTexts();
    }

    public virtual void SetBusy(bool busy) { }

    public virtual bool HasPendingEdit => false;
    public virtual Task CommitAsync() => Task.CompletedTask;
    public virtual void DropEdit() { }

    protected Task<SettingsAnswer?> Send(SettingsRequest? request) =>
        request is null ? Task.FromResult<SettingsAnswer?>(null) : Context.Page.SendAsync(request, this);

    /// <summary>The control's accessible name (the label, or what it does in the field), help and automation id.</summary>
    protected void Identify(FrameworkElement control, string role = "", string? name = null)
    {
        AutomationProperties.SetAutomationId(control, Field.Id + (role.Length > 0 ? "/" + role : ""));
        AutomationProperties.SetName(control, name ?? Field.Label);
        if (Field.Help is { } text && role.Length == 0) AutomationProperties.SetHelpText(control, text);
    }

    /// <summary>The card around <paramref name="control"/>: beside the texts, or under them (<paramref name="wide"/>).</summary>
    protected void Build(FrameworkElement? control, bool wide)
    {
        var texts = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(label);
        texts.Children.Add(help);
        texts.Children.Add(status);
        texts.Children.Add(problem);
        var grid = Layout;
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        if (wide && control is not null) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.Children.Add(texts);
        if (control is not null)
        {
            if (wide)
            {
                Grid.SetRow(control, 1);
                Grid.SetColumnSpan(control, 2);
            }
            else
            {
                Grid.SetColumn(control, 1);
                control.VerticalAlignment = VerticalAlignment.Center;
            }
            grid.Children.Add(control);
        }
        Root = new Border { Child = grid, Style = Styles.Get("CardStyle") };
        ShowTexts();
        ShowProblem(null);
    }

    protected void ShowTexts()
    {
        label.Text = Field.Label;
        help.Text = Field.Help ?? "";
        help.Visibility = Field.Help is null ? Visibility.Collapsed : Visibility.Visible;
        var state = StatusText();
        status.Text = state ?? "";
        status.Visibility = state is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>The line under the help: the field's state (a key's, a value in words), or what its action said.</summary>
    protected virtual string? StatusText() => Field.Status is { Length: > 0 } text ? text : outcome;

    /// <summary>Asks before an action that deletes; true to go on.</summary>
    protected async Task<bool> ConfirmAsync(string action, bool onItem, string name)
    {
        if (Context.Text.Confirmation(action, onItem, name) is not { } question) return true;
        var dialog = new ContentDialog
        {
            Title = question,
            PrimaryButtonText = Context.Text.Action(action, onItem).TrimEnd('…', '.'),
            CloseButtonText = Context.Text["cancel"],
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = Context.Page.XamlRoot,
            RequestedTheme = Context.Page.Theme,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    protected static Button IconButton(string glyph, string name, string automationId)
    {
        var button = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 14 }, Padding = new Thickness(8, 6, 8, 6) };
        ToolTipService.SetToolTip(button, name);
        AutomationProperties.SetName(button, name);
        AutomationProperties.SetAutomationId(button, automationId);
        return button;
    }
}

/// <summary><c>toggle</c>: a switch.</summary>
sealed class ToggleCard : FieldCard
{
    readonly ToggleSwitch toggle = new() { OnContent = "", OffContent = "", MinWidth = 0 };
    bool updating;

    /// <summary>The switch alone, out of its card, for a list's entry that is nothing else (the card isn't shown).</summary>
    public ToggleSwitch TakeSwitch()
    {
        Layout.Children.Remove(toggle);
        return toggle;
    }

    public ToggleCard(Field field, CardContext context) : base(field, context)
    {
        Identify(toggle);
        toggle.IsOn = Field.BoolValue == true;
        toggle.IsEnabled = Enabled;
        toggle.Toggled += async (_, _) =>
        {
            if (!updating) await Send(FieldPresenter.Toggled(Field, toggle.IsOn));
        };
        Build(toggle, wide: false);
    }

    protected override void Update(Field old)
    {
        updating = true;
        toggle.IsOn = Field.BoolValue == true;
        toggle.IsEnabled = Enabled;
        AutomationProperties.SetName(toggle, Field.Label);
        updating = false;
    }
}

/// <summary><c>integer</c>: a number box with its bounds and step, committed as it is (Enter, the arrows, focus leaving).</summary>
sealed class NumberCard : FieldCard
{
    readonly NumberBox box = new() { SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline, MinWidth = 160 };
    bool updating;

    public NumberCard(Field field, CardContext context) : base(field, context)
    {
        Identify(box);
        box.Minimum = Field.Min ?? double.MinValue;
        box.Maximum = Field.Max ?? double.MaxValue;
        box.SmallChange = Field.Step ?? 1;
        box.LargeChange = (Field.Step ?? 1) * 10;
        box.ValidationMode = NumberBoxValidationMode.InvalidInputOverwritten;
        Update(field);
        box.ValueChanged += async (_, args) =>
        {
            if (!updating) await Send(FieldPresenter.Integer(Field, args.NewValue));
        };
        Build(box, wide: false);
    }

    protected override void Update(Field old)
    {
        updating = true;
        box.Value = Field.NumberValue ?? double.NaN;
        box.IsEnabled = Enabled;
        AutomationProperties.SetName(box, Field.Label);
        updating = false;
    }
}

/// <summary><c>number</c>: a slider (and, when it is optional, a box that sends it at all); its value in words under
/// the label. Sent once the slider rests.</summary>
sealed class SliderCard : FieldCard
{
    readonly Slider slider = new() { MinWidth = 240 };
    readonly CheckBox? on;
    readonly DispatcherTimer rest = new() { Interval = TimeSpan.FromMilliseconds(400) };
    bool updating;

    public SliderCard(Field field, CardContext context) : base(field, context)
    {
        Identify(slider);
        slider.Minimum = Field.Min ?? 0;
        slider.Maximum = Field.Max ?? 100;
        var step = Field.Step ?? (slider.Maximum - slider.Minimum) / 100;
        slider.StepFrequency = step;
        slider.SmallChange = step;
        slider.LargeChange = step * 5;
        rest.Tick += async (_, _) =>
        {
            rest.Stop();
            await Send(on is null ? FieldPresenter.Number(Field, slider.Value) : FieldPresenter.OptionalNumber(Field, on.IsChecked == true, slider.Value));
        };
        slider.ValueChanged += (_, _) =>
        {
            if (updating) return;
            rest.Stop();
            rest.Start();
        };
        FrameworkElement control = slider;
        if (Field.Optional)
        {
            on = new CheckBox { MinWidth = 0 };
            Identify(on, "on");
            on.Checked += async (_, _) => { if (!updating) await Send(FieldPresenter.OptionalNumber(Field, true, slider.Value)); };
            on.Unchecked += async (_, _) => { if (!updating) await Send(FieldPresenter.OptionalNumber(Field, false, slider.Value)); };
            var both = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            both.Children.Add(on);
            both.Children.Add(slider);
            control = both;
        }
        Update(field);
        Build(control, wide: false);
    }

    protected override void Update(Field old)
    {
        updating = true;
        slider.Value = Field.NumberValue ?? slider.Value;
        if (on is not null)
        {
            on.IsChecked = Field.Value is not null;
            on.IsEnabled = Enabled;
            slider.IsEnabled = Enabled && Field.Value is not null;
        }
        else
        {
            slider.IsEnabled = Enabled;
        }
        updating = false;
    }
}

/// <summary><c>text</c> and <c>words</c>: a box, committed on Enter (Ctrl+Enter for several lines) or when the focus
/// leaves it, put back by Escape; suggestions in a menu beside it, a picker for a folder or a file.</summary>
sealed class TextCard : FieldCard
{
    readonly TextBox box = new() { MinWidth = 300 };
    string shown;

    public TextCard(Field field, CardContext context) : base(field, context)
    {
        Identify(box);
        shown = Current(field);
        box.Text = shown;
        box.PlaceholderText = Field.Placeholder ?? "";
        if (Field.Multiline)
        {
            box.AcceptsReturn = true;
            box.TextWrapping = TextWrapping.Wrap;
            box.MinHeight = 96;
        }
        box.IsEnabled = Enabled;
        box.KeyDown += async (_, args) =>
        {
            if (args.Key == VirtualKey.Enter && (!Field.Multiline || IsDown(VirtualKey.Control)))
            {
                args.Handled = true;
                await CommitAsync();
            }
            else if (args.Key == VirtualKey.Escape && box.Text != shown)
            {
                args.Handled = true;
                box.Text = shown;
            }
        };
        box.LostFocus += async (_, _) => await CommitAsync();

        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(box);
        var extras = new List<FrameworkElement>();
        if (Field.Choices.Count > 0)
        {
            var menu = new MenuFlyout { Placement = FlyoutPlacementMode.BottomEdgeAlignedRight };
            foreach (var choice in Field.Choices)
            {
                var item = new MenuFlyoutItem { Text = choice.Note is null ? choice.Label : $"{choice.Label} — {choice.Note}" };
                item.Click += async (_, _) =>
                {
                    box.Text = (string?)choice.Value ?? "";
                    await CommitAsync();
                };
                menu.Items.Add(item);
            }
            var suggestions = new DropDownButton { Content = Context.Text["choose"], Flyout = menu, IsEnabled = Enabled };
            Identify(suggestions, "suggestions", $"{Field.Label}: {Context.Text["choose"]}");
            extras.Add(suggestions);
        }
        if (Field.Pick is { } pick)
        {
            var choose = new Button { Content = Context.Text["choose"], IsEnabled = Enabled };
            Identify(choose, "pick", $"{Field.Label}: {Context.Text["choose"]}");
            choose.Click += async (_, _) =>
            {
                if (await Pickers.PickAsync(pick, Context.Page.WindowHandle) is { } path)
                {
                    box.Text = path;
                    await CommitAsync();
                }
            };
            extras.Add(choose);
        }
        foreach (var extra in extras)
        {
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(extra, row.ColumnDefinitions.Count - 1);
            extra.VerticalAlignment = Field.Multiline ? VerticalAlignment.Top : VerticalAlignment.Center;
            row.Children.Add(extra);
        }
        Build(row, FieldPresenter.IsWide(field));
    }

    static string Current(Field field) => field.Kind == "words" ? FieldPresenter.WordsLine(field) : field.StringValue ?? "";

    static bool IsDown(VirtualKey key) =>
        Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

    public override bool HasPendingEdit => box.Text != shown;

    public override async Task CommitAsync()
    {
        if (box.Text == shown) return;
        var request = Field.Kind == "words" ? FieldPresenter.Words(Field, box.Text) : FieldPresenter.Text(Field, box.Text);
        shown = box.Text;
        await Send(request);
    }

    public override void DropEdit() => shown = box.Text;

    protected override void Update(Field old)
    {
        var now = Current(Field);
        // A text being typed stays as it is; one left alone shows what the engine has now.
        var typing = box.FocusState != FocusState.Unfocused && box.Text != Current(old);
        if (!typing) box.Text = now;
        shown = now;
        box.PlaceholderText = Field.Placeholder ?? "";
        box.IsEnabled = Enabled;
        AutomationProperties.SetName(box, Field.Label);
    }
}

/// <summary><c>choice</c>: a drop-down; a choice shown but not to be picked is greyed.</summary>
sealed class ComboCard : FieldCard
{
    readonly ComboBox combo = new() { MinWidth = 220 };
    bool updating;

    public ComboCard(Field field, CardContext context) : base(field, context)
    {
        Identify(combo);
        foreach (var choice in Field.Choices)
        {
            var item = new ComboBoxItem { Content = choice.Label, IsEnabled = !choice.Disabled };
            AutomationProperties.SetName(item, choice.Label);
            if (choice.Note is { } note) ToolTipService.SetToolTip(item, note);
            combo.Items.Add(item);
        }
        Update(field);
        combo.SelectionChanged += async (_, _) =>
        {
            if (!updating) await Send(FieldPresenter.Picked(Field, combo.SelectedIndex));
        };
        Build(combo, wide: false);
    }

    protected override void Update(Field old)
    {
        updating = true;
        combo.SelectedIndex = FieldPresenter.SelectedChoice(Field);
        combo.IsEnabled = Enabled;
        AutomationProperties.SetName(combo, Field.Label);
        updating = false;
    }
}

/// <summary><c>choices</c> not ordered: a check box each, in two columns when they are short.</summary>
sealed class CheckListCard : FieldCard
{
    readonly List<CheckBox> boxes = [];
    bool updating;

    public CheckListCard(Field field, CardContext context) : base(field, context)
    {
        var columns = Field.Choices.All(c => c.Note is null && c.Label.Length <= 24) ? 2 : 1;
        var grid = new Grid { ColumnSpacing = 24 };
        for (var c = 0; c < columns; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var rows = (Field.Choices.Count + columns - 1) / columns;
        for (var r = 0; r < rows; r++) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (var i = 0; i < Field.Choices.Count; i++)
        {
            var choice = Field.Choices[i];
            var index = i;
            var box = new CheckBox { Content = Label(choice), IsEnabled = Enabled && !choice.Disabled };
            AutomationProperties.SetName(box, choice.Label);
            if (choice.Note is { } note) AutomationProperties.SetHelpText(box, note);
            AutomationProperties.SetAutomationId(box, Field.Id + "/" + ((string?)choice.Value ?? index.ToString()));
            box.Checked += async (_, _) => { if (!updating) await Send(FieldPresenter.Checked(Field, index, true)); };
            box.Unchecked += async (_, _) => { if (!updating) await Send(FieldPresenter.Checked(Field, index, false)); };
            Grid.SetRow(box, index / columns);
            Grid.SetColumn(box, index % columns);
            grid.Children.Add(box);
            boxes.Add(box);
        }
        AutomationProperties.SetName(grid, Field.Label);
        Update(field);
        Build(grid, wide: true);
    }

    static object Label(Choice choice)
    {
        if (choice.Note is null) return choice.Label;
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = choice.Label, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = choice.Note, Style = Styles.Get("SecondaryTextStyle") });
        return panel;
    }

    protected override void Update(Field old)
    {
        updating = true;
        for (var i = 0; i < boxes.Count; i++)
        {
            boxes[i].IsChecked = FieldPresenter.IsPicked(Field, i);
            boxes[i].IsEnabled = Enabled && !Field.Choices[i].Disabled;
        }
        updating = false;
    }
}

/// <summary><c>choices</c> in order: the picked ones, first the default, each moved up, down or removed; one to add.</summary>
sealed class OrderedListCard : FieldCard
{
    readonly StackPanel rows = new() { Spacing = 4 };
    readonly DropDownButton add = new();

    public OrderedListCard(Field field, CardContext context) : base(field, context)
    {
        add.Content = Context.Text["add"];
        Identify(add, "add", $"{Field.Label}: {Context.Text["add"]}");
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(rows);
        panel.Children.Add(add);
        AutomationProperties.SetName(rows, Field.Label);
        Fill();
        Build(panel, wide: true);
    }

    protected override void Update(Field old) => Fill();

    void Fill()
    {
        rows.Children.Clear();
        var values = FieldPresenter.PickedValues(Field);
        for (var i = 0; i < values.Count; i++)
        {
            var position = i;
            var text = FieldPresenter.LabelOf(Field, values[i]);
            var key = (string?)values[i] ?? i.ToString();
            var row = new Grid { ColumnSpacing = 4, Padding = new Thickness(8, 2, 0, 2) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (var c = 0; c < 3; c++) row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap };
            if (Field.Choices.FirstOrDefault(c => c.Is(values[i]))?.Note is { } note) ToolTipService.SetToolTip(name, note);
            row.Children.Add(name);
            var up = IconButton("", $"{Context.Text["moveUp"]}: {text}", $"{Field.Id}/up/{key}");
            var down = IconButton("", $"{Context.Text["moveDown"]}: {text}", $"{Field.Id}/down/{key}");
            var remove = IconButton("", $"{Context.Text["remove"]}: {text}", $"{Field.Id}/remove/{key}");
            up.IsEnabled = Enabled && i > 0;
            down.IsEnabled = Enabled && i < values.Count - 1;
            remove.IsEnabled = Enabled && values.Count > (Field.MinCount ?? 0);
            up.Click += async (_, _) => await Send(FieldPresenter.Moved(Field, position, -1));
            down.Click += async (_, _) => await Send(FieldPresenter.Moved(Field, position, 1));
            remove.Click += async (_, _) => await Send(FieldPresenter.Removed(Field, position));
            foreach (var (button, column) in new[] { (up, 1), (down, 2), (remove, 3) })
            {
                Grid.SetColumn(button, column);
                row.Children.Add(button);
            }
            rows.Children.Add(row);
        }
        var menu = new MenuFlyout();
        foreach (var choice in FieldPresenter.Addable(Field))
        {
            var item = new MenuFlyoutItem { Text = choice.Note is null ? choice.Label : $"{choice.Label} — {choice.Note}" };
            item.Click += async (_, _) => await Send(FieldPresenter.Added(Field, choice));
            menu.Items.Add(item);
        }
        add.Flyout = menu;
        add.IsEnabled = Enabled && menu.Items.Count > 0 && values.Count < (Field.MaxCount ?? int.MaxValue);
    }
}

/// <summary><c>secret</c>: whether it is set and its last characters (never the key), a box to paste a new one, Save,
/// and Remove… when it has the action. The box is cleared as the key is sent, once.</summary>
sealed class SecretCard : FieldCard
{
    readonly PasswordBox box = new() { MinWidth = 280 };
    readonly Button save = new();
    readonly Button remove = new();

    public SecretCard(Field field, CardContext context) : base(field, context)
    {
        Identify(box);
        box.PlaceholderText = Context.Text["paste"];
        save.Content = Context.Text.Action("setKey");
        Identify(save, "setKey", $"{Field.Label}: {Context.Text.Action("setKey")}");
        remove.Content = Context.Text.Action("removeKey");
        Identify(remove, "removeKey", $"{Field.Label}: {Context.Text.Action("removeKey")}");
        box.KeyDown += async (_, args) =>
        {
            if (args.Key != VirtualKey.Enter) return;
            args.Handled = true;
            await SaveAsync();
        };
        save.Click += async (_, _) => await SaveAsync();
        remove.Click += async (_, _) =>
        {
            if (await ConfirmAsync("removeKey", onItem: false, Field.Label)) await Send(FieldPresenter.RemoveSecret(Field));
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(box);
        row.Children.Add(save);
        row.Children.Add(remove);
        Update(field);
        Build(row, wide: true);
    }

    async Task SaveAsync()
    {
        var request = FieldPresenter.SaveSecret(Field, box.Password);
        box.Password = "";
        await Send(request);
    }

    protected override void Update(Field old)
    {
        box.IsEnabled = save.IsEnabled = Enabled && Field.Actions.Contains("setKey");
        remove.Visibility = Field.Actions.Contains("removeKey") ? Visibility.Visible : Visibility.Collapsed;
        remove.IsEnabled = Enabled;
        AutomationProperties.SetName(box, Field.Label);
    }
}

/// <summary><c>info</c>, and a kind this window doesn't know: the text, to read and copy.</summary>
sealed class InfoCard : FieldCard
{
    readonly TextBlock text = new() { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };

    public InfoCard(Field field, CardContext context) : base(field, context)
    {
        Identify(text);
        Update(field);
        Build(text, wide: true);
    }

    protected override void Update(Field old)
    {
        text.Text = Field.StringValue ?? Field.Value?.ToJsonString() ?? "";
        text.Visibility = text.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetName(text, Field.Label);
    }
}

/// <summary><c>button</c>: its action (Test Connection), with a box for what it takes when it has a placeholder (a
/// link); a ring while it runs, and its last outcome under the label.</summary>
sealed class ButtonCard : FieldCard
{
    readonly Button button = new();
    readonly ProgressRing ring = new() { Width = 20, Height = 20, IsActive = false };
    readonly TextBox? value;
    bool busy;

    public ButtonCard(Field field, CardContext context) : base(field, context)
    {
        button.Content = ActionWord();
        Identify(button);
        AutomationProperties.SetName(ring, Context.Text["working"]);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (Field.Placeholder is { } placeholder)
        {
            value = new TextBox { PlaceholderText = placeholder, MinWidth = 320 };
            Identify(value, "value");
            row.Children.Add(value);
        }
        row.Children.Add(button);
        row.Children.Add(ring);
        button.Click += async (_, _) => await Send(FieldPresenter.Run(Field, value?.Text));
        busy = Context.Page.Busy.Contains(Field.Id);
        Update(field);
        Build(row, FieldPresenter.IsWide(field));
    }

    public override void SetBusy(bool on)
    {
        busy = on;
        Update(Field);
        ShowTexts();
    }

    protected override string? StatusText() => busy ? Context.Text["working"] : base.StatusText();

    /// <summary>The button's word: its action's ("Test"), as the window's words have it.</summary>
    string ActionWord() => Field.Actions.Count > 0 ? Context.Text.Action(Field.Actions[0]) : Field.Label;

    protected override void Update(Field old)
    {
        button.Content = ActionWord();
        AutomationProperties.SetName(button, Field.Label);
        button.IsEnabled = Enabled && !busy && Field.Actions.Count > 0;
        ring.IsActive = busy;
        ring.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        if (value is not null) value.IsEnabled = Enabled && !busy;
    }
}

/// <summary>The app's looks (App.xaml): styles whose brushes follow the theme of the element they are on.</summary>
static class Styles
{
    public static Style Get(string name) => (Style)Application.Current.Resources[name];
}

/// <summary>Folders and files picked for a field (<c>pick</c>).</summary>
static class Pickers
{
    public static async Task<string?> PickAsync(string kind, IntPtr window)
    {
        if (kind == "folder")
        {
            var picker = new Windows.Storage.Pickers.FolderPicker();
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, window);
            return (await picker.PickSingleFolderAsync())?.Path;
        }
        var files = new Windows.Storage.Pickers.FileOpenPicker();
        files.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(files, window);
        return (await files.PickSingleFileAsync())?.Path;
    }
}
