// webview2host: the end-to-end driver's WebView2 app (run-e2e.sh --webview2). A window with a WebView2 filling it, a
// page with one text field in it, focused; what the field holds goes to --value-file each time it changes (UTF-8, written
// whole, then moved into place), and --value-file plus ".ready" is written once the field has the focus. WebView2's own
// data goes in --user-data, the run's folder, never the user's.
//
//   webview2host --user-data <dir> --value-file <file>

using System;
using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

static class Program
{
    const string Page = """
        <!doctype html>
        <meta charset="utf-8">
        <title>AllInOneIME e2e</title>
        <textarea id="field" autofocus style="width: 95%; height: 80vh; font-size: 20px"></textarea>
        <script>
          const field = document.getElementById("field");
          const send = () => chrome.webview.postMessage(field.value);
          field.addEventListener("input", send);
          field.addEventListener("compositionend", send);
        </script>
        """;

    [STAThread]
    static void Main(string[] args)
    {
        string? userData = null, valueFile = null;
        for (int i = 0; i + 1 < args.Length; i += 2)
        {
            if (args[i] == "--user-data") userData = args[i + 1];
            else if (args[i] == "--value-file") valueFile = args[i + 1];
        }
        if (userData == null || valueFile == null)
        {
            Console.Error.WriteLine("usage: webview2host --user-data <dir> --value-file <file>");
            Environment.Exit(2);
        }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        var form = new Form
        {
            Text = "AllInOneIME e2e WebView2",
            StartPosition = FormStartPosition.Manual,
            Left = 60,
            Top = 60,
            Width = 640,
            Height = 360,
        };
        var view = new WebView2 { Dock = DockStyle.Fill };
        form.Controls.Add(view);
        form.Shown += async (_, _) =>
        {
            var environment = await CoreWebView2Environment.CreateAsync(null, userData);
            await view.EnsureCoreWebView2Async(environment);
            view.CoreWebView2.WebMessageReceived += (_, message) =>
            {
                string temporary = valueFile + ".tmp";
                File.WriteAllText(temporary, message.TryGetWebMessageAsString());
                File.Move(temporary, valueFile, true);
            };
            view.CoreWebView2.NavigationCompleted += async (_, _) =>
            {
                view.Focus();
                await view.CoreWebView2.ExecuteScriptAsync("document.getElementById('field').focus()");
                File.WriteAllText(valueFile + ".ready", "ready");
            };
            view.NavigateToString(Page);
        };
        Application.Run(form);
    }
}
