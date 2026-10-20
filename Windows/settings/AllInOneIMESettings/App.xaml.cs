using System.Runtime.InteropServices;
using AllInOneIME.Settings.Wire;
using Microsoft.UI.Xaml;

namespace AllInOneIME.Settings;

/// <summary>
/// AllInOneIME Settings: the engine's settings document drawn as a window (wire protocol §12). One window per engine
/// (a second start brings the first one forward), started from the Start menu or by @settings.
/// </summary>
public partial class App : Application
{
    MainWindow? window;
    EventWaitHandle? instance;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppOptions options;
        try
        {
            options = AppOptions.Parse(Environment.GetCommandLineArgs().Skip(1).ToList());
        }
        catch (ArgumentException)
        {
            options = new AppOptions();
        }
        var pipe = PipeNames.Full(options.Pipe ?? PipeNames.UserPipe);

        // One window per engine: a second start tells the first to come forward, and quits. (Screenshots always draw.)
        if (options.Screenshots is null)
        {
            instance = new EventWaitHandle(false, EventResetMode.AutoReset, PipeNames.SettingsInstance(pipe), out var created);
            if (!created)
            {
                AllowSetForegroundWindow(-1);  // it may take the foreground this start was given (by @settings)
                instance.Set();
                Exit();
                return;
            }
        }

        window = new MainWindow(options, pipe);
        window.Activate();
        if (instance is not null)
        {
            var handle = instance;
            var dispatcher = window.DispatcherQueue;
            new Thread(() =>
            {
                while (handle.WaitOne()) dispatcher.TryEnqueue(() => window?.BringForward());
            }) { IsBackground = true, Name = "settings instance" }.Start();
        }
    }

    [DllImport("user32.dll")]
    static extern bool AllowSetForegroundWindow(int processId);
}
