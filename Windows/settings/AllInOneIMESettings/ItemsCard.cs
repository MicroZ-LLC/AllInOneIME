using System.Text.Json.Nodes;
using AllInOneIME.Settings.Document;
using AllInOneIME.Settings.Presentation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace AllInOneIME.Settings;

/// <summary>
/// <c>items</c>: a list (plugins, apps, folders, extensions, custom commands). Each entry has its title, detail and
/// actions; one with fields of its own (an app's settings, an extension's switch and preferences) opens to show them
/// as cards. The list's own actions: <c>add</c> with a box (suggestions, a picker), a new entry through the field's
/// <c>form</c>, the others as buttons.
/// </summary>
sealed class ItemsCard : FieldCard
{
    readonly StackPanel list = new() { Spacing = 4 };
    readonly Dictionary<string, FieldCard> nested = [];
    readonly Dictionary<string, (TextBlock title, TextBlock detail)> headers = [];
    TextBox? addBox;

    public ItemsCard(Field field, CardContext context) : base(field, context)
    {
        var panel = new StackPanel { Spacing = 8 };
        AutomationProperties.SetName(list, Field.Label);
        panel.Children.Add(list);
        foreach (var item in Field.Items) list.Children.Add(Entry(item));
        if (Field.Actions.Contains("add")) panel.Children.Add(AddRow());
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var action in FieldPresenter.ListActions(Field))
        {
            var button = new Button { Content = Context.Text.Action(action), IsEnabled = Enabled };
            AutomationProperties.SetAutomationId(button, Field.Id + "/" + action);
            AutomationProperties.SetName(button, $"{Field.Label}: {Context.Text.Action(action)}");
            button.Click += async (_, _) =>
            {
                if (action == "save" && Field.Form.Count > 0) await EditAsync(null);
                else await Send(FieldPresenter.FieldAction(Field, action));
            };
            buttons.Children.Add(button);
        }
        if (buttons.Children.Count > 0) panel.Children.Add(buttons);
        Build(panel, wide: true);
    }

    string Key(Item item) => Field.Id + "|" + item.Id;

    FrameworkElement Entry(Item item)
    {
        var title = new TextBlock { Text = item.Title, TextWrapping = TextWrapping.Wrap, Style = Styles.Get("BodyStrongTextBlockStyle") };
        var detail = new TextBlock
        {
            Text = item.Detail ?? "", IsTextSelectionEnabled = true, Style = Styles.Get("SecondaryTextStyle"),
            Visibility = item.Detail is null ? Visibility.Collapsed : Visibility.Visible,
        };
        headers[item.Id] = (title, detail);
        var texts = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(title);
        texts.Children.Add(detail);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        foreach (var action in item.Actions)
        {
            var label = Context.Text.Action(action, onItem: true);
            var button = new Button { Content = label, IsEnabled = Enabled };
            AutomationProperties.SetAutomationId(button, Field.Id + "/" + action + "/" + item.Id);
            AutomationProperties.SetName(button, $"{label} {item.Title}");
            button.Click += async (_, _) =>
            {
                if (action == "save" && Field.Form.Count > 0) await EditAsync(item);
                else if (await ConfirmAsync(action, onItem: true, item.Title)) await Send(FieldPresenter.ItemAction(Field, item, action));
            };
            actions.Children.Add(button);
        }
        // An entry whose one field is its switch (a script's): the switch in its row.
        if (item.Fields is [{ Kind: "toggle" } only])
        {
            var card = (ToggleCard)Create(only, Context);
            nested[only.Id] = card;
            actions.Children.Insert(0, card.TakeSwitch());
        }
        if (item.Fields.Count == 0 || item.Fields is [{ Kind: "toggle" }])
        {
            var row = new Grid { ColumnSpacing = 12, Style = Styles.Get("EntryStyle") };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(actions, 1);
            row.Children.Add(texts);
            row.Children.Add(actions);
            AutomationProperties.SetName(row, item.Title);
            return row;
        }
        // An entry with settings of its own: they show when it is opened, its actions with them.
        var content = new StackPanel { Spacing = 4 };
        foreach (var field in item.Fields)
        {
            var card = Create(field, Context);
            nested[field.Id] = card;
            content.Children.Add(card.Root);
        }
        if (actions.Children.Count > 0)
        {
            actions.HorizontalAlignment = HorizontalAlignment.Right;
            actions.Margin = new Thickness(0, 4, 0, 0);
            content.Children.Add(actions);
        }
        var expander = new Expander
        {
            Header = texts, Content = content, HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            IsExpanded = Context.Page.ExpandAll || Context.Page.Expanded.GetValueOrDefault(Key(item)),
        };
        AutomationProperties.SetName(expander, item.Title);
        AutomationProperties.SetAutomationId(expander, Field.Id + "/" + item.Id);
        expander.Expanding += (_, _) => Context.Page.Expanded[Key(item)] = true;
        expander.Collapsed += (_, _) => Context.Page.Expanded[Key(item)] = false;
        return expander;
    }

    /// <summary>The box an app or a folder is added with: suggestions (the apps typed in lately), a picker, Add.</summary>
    FrameworkElement AddRow()
    {
        addBox = new TextBox { PlaceholderText = Field.Placeholder ?? "", MinWidth = 280, IsEnabled = Enabled };
        AutomationProperties.SetAutomationId(addBox, Field.Id + "/addValue");
        AutomationProperties.SetName(addBox, $"{Field.Label}: {Context.Text.Action("add")}");
        var add = new Button { Content = Context.Text.Action("add"), IsEnabled = Enabled };
        AutomationProperties.SetAutomationId(add, Field.Id + "/add");
        AutomationProperties.SetName(add, $"{Field.Label}: {Context.Text.Action("add")}");
        add.Click += async (_, _) => await AddAsync();
        addBox.KeyDown += async (_, args) =>
        {
            if (args.Key != VirtualKey.Enter) return;
            args.Handled = true;
            await AddAsync();
        };
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(addBox);
        void Column(FrameworkElement element)
        {
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(element, row.ColumnDefinitions.Count - 1);
            row.Children.Add(element);
        }
        if (Field.Choices.Count > 0)
        {
            var menu = new MenuFlyout { Placement = FlyoutPlacementMode.BottomEdgeAlignedRight };
            foreach (var choice in Field.Choices.Where(c => !c.Disabled))
            {
                var item = new MenuFlyoutItem { Text = choice.Label };
                item.Click += async (_, _) => await Send(FieldPresenter.Add(Field, (string?)choice.Value ?? ""));
                menu.Items.Add(item);
            }
            var suggestions = new DropDownButton { Content = Context.Text["choose"], Flyout = menu, IsEnabled = Enabled };
            AutomationProperties.SetAutomationId(suggestions, Field.Id + "/suggestions");
            AutomationProperties.SetName(suggestions, $"{Field.Label}: {Context.Text["choose"]}");
            Column(suggestions);
        }
        else if (Field.Pick is { } pick)
        {
            var choose = new Button { Content = Context.Text["choose"], IsEnabled = Enabled };
            AutomationProperties.SetAutomationId(choose, Field.Id + "/pick");
            AutomationProperties.SetName(choose, $"{Field.Label}: {Context.Text["choose"]}");
            choose.Click += async (_, _) =>
            {
                if (await Pickers.PickAsync(pick, Context.Page.WindowHandle) is { } path) await Send(FieldPresenter.Add(Field, path));
            };
            Column(choose);
        }
        Column(add);
        return row;
    }

    async Task AddAsync()
    {
        if (addBox is null) return;
        var answer = await Send(FieldPresenter.Add(Field, addBox.Text));
        if (answer is { Problem: null }) addBox.Text = "";
    }

    /// <summary>The field's form for <paramref name="item"/> (null: a new one); saved through the engine, which says
    /// what keeps it from being saved (the dialog stays open then).</summary>
    async Task EditAsync(Item? item)
    {
        var values = FieldPresenter.FormValues(Field, item);
        var form = new FormView(Field.Form, values, Enabled);
        var problem = new TextBlock { Visibility = Visibility.Collapsed, Style = Styles.Get("ProblemTextStyle") };
        AutomationProperties.SetLiveSetting(problem, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Assertive);
        form.Panel.Children.Add(problem);
        var dialog = new ContentDialog
        {
            Title = item?.Title ?? Field.Label,
            Content = new ScrollViewer { Content = form.Panel, MaxHeight = 520 },
            PrimaryButtonText = Context.Text["save"],
            CloseButtonText = Context.Text["cancel"],
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = Context.Page.XamlRoot,
            RequestedTheme = Context.Page.Theme,
        };
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                var answer = await Send(FieldPresenter.SaveForm(Field, item, form.Values));
                if (answer?.Problem is { } refused)
                {
                    args.Cancel = true;
                    problem.Text = refused.Message;
                    problem.Visibility = Visibility.Visible;
                }
                else if (answer is null)
                {
                    args.Cancel = true;
                }
            }
            finally
            {
                deferral.Complete();
            }
        };
        await dialog.ShowAsync();
    }

    public override bool TryUpdate(Field field, CardContext context)
    {
        // The same entries with the same actions and fields: their texts and fields updated in place.
        if (FieldPresenter.ControlFor(field) != FieldControl.Items || !SameEntries(Field, field)) return false;
        foreach (var item in field.Items)
        {
            if (headers.TryGetValue(item.Id, out var header))
            {
                header.title.Text = item.Title;
                header.detail.Text = item.Detail ?? "";
                header.detail.Visibility = item.Detail is null ? Visibility.Collapsed : Visibility.Visible;
            }
            foreach (var inner in item.Fields)
            {
                if (!nested.TryGetValue(inner.Id, out var card) || !card.TryUpdate(inner, context)) return false;
            }
        }
        return base.TryUpdate(StripItems(field, Field), context);
    }

    /// <summary>The same entries (ids, actions, their fields' ids and kinds) and the same list.</summary>
    static bool SameEntries(Field a, Field b)
    {
        if (a.Items.Count != b.Items.Count || !a.Actions.SequenceEqual(b.Actions)) return false;
        for (var i = 0; i < a.Items.Count; i++)
        {
            var (x, y) = (a.Items[i], b.Items[i]);
            if (x.Id != y.Id || !x.Actions.SequenceEqual(y.Actions) || x.Fields.Count != y.Fields.Count
                || !JsonNode.DeepEquals(x.Value, y.Value)) return false;
            if (x.Fields.Zip(y.Fields).Any(pair => pair.First.Id != pair.Second.Id || pair.First.Kind != pair.Second.Kind)) return false;
        }
        return true;
    }

    /// <summary>The field with the items as the card has them, so that the base compares the rest of it.</summary>
    static Field StripItems(Field field, Field current)
    {
        var json = (JsonObject)field.Json.DeepClone();
        json["items"] = current.Json["items"]?.DeepClone();
        return Field.Parse(json);
    }

    public override FieldCard? Find(string id) =>
        Field.Id == id ? this : nested.Values.Select(card => card.Find(id)).FirstOrDefault(card => card is not null);
}

/// <summary>A form's fields (a custom command's editor): a text, several lines, a choice, a command line, a switch,
/// each shown while its <c>when</c> holds.</summary>
sealed class FormView
{
    readonly IReadOnlyList<Field> fields;
    readonly Dictionary<string, JsonNode?> values;
    readonly Dictionary<string, FrameworkElement> rows = [];

    public FormView(IReadOnlyList<Field> fields, Dictionary<string, JsonNode?> values, bool enabled)
    {
        this.fields = fields;
        this.values = values;
        foreach (var field in fields)
        {
            var row = new StackPanel { Spacing = 4 };
            row.Children.Add(new TextBlock { Text = field.Label, TextWrapping = TextWrapping.Wrap });
            FrameworkElement control;
            switch (field.Kind)
            {
                case "choice":
                    var combo = new ComboBox { MinWidth = 260, IsEnabled = enabled };
                    foreach (var choice in field.Choices) combo.Items.Add(new ComboBoxItem { Content = choice.Label, IsEnabled = !choice.Disabled });
                    combo.SelectedIndex = field.Choices.ToList().FindIndex(c => c.Is(values.GetValueOrDefault(field.Id)));
                    combo.SelectionChanged += (_, _) =>
                    {
                        if (combo.SelectedIndex < 0) return;
                        values[field.Id] = field.Choices[combo.SelectedIndex].Value?.DeepClone();
                        ShowRows();
                    };
                    control = combo;
                    break;
                case "toggle":
                    var toggle = new ToggleSwitch { OnContent = "", OffContent = "", IsOn = values.GetValueOrDefault(field.Id) is JsonValue v && v.TryGetValue<bool>(out var on) && on, IsEnabled = enabled };
                    toggle.Toggled += (_, _) => values[field.Id] = JsonValue.Create(toggle.IsOn);
                    control = toggle;
                    break;
                default:
                    var box = new TextBox
                    {
                        Text = (string?)values.GetValueOrDefault(field.Id) ?? "", PlaceholderText = field.Placeholder ?? "",
                        AcceptsReturn = field.Multiline, TextWrapping = field.Multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
                        MinHeight = field.Multiline ? 96 : 0, MinWidth = 420, IsEnabled = enabled,
                    };
                    box.TextChanged += (_, _) => values[field.Id] = JsonValue.Create(box.Text);
                    control = box;
                    break;
            }
            AutomationProperties.SetName(control, field.Label);
            AutomationProperties.SetAutomationId(control, "form/" + field.Id);
            if (field.Help is { } help)
            {
                AutomationProperties.SetHelpText(control, help);
                row.Children.Add(new TextBlock { Text = help, Style = Styles.Get("SecondaryTextStyle") });
            }
            row.Children.Add(control);
            rows[field.Id] = row;
            Panel.Children.Add(row);
        }
        ShowRows();
    }

    public StackPanel Panel { get; } = new() { Spacing = 12, MinWidth = 440 };
    public IReadOnlyDictionary<string, JsonNode?> Values => values;

    void ShowRows()
    {
        foreach (var field in fields)
        {
            rows[field.Id].Visibility = FieldPresenter.IsShown(field, values) ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}
