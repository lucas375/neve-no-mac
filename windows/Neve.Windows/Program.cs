using System.Windows;

namespace Neve.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var instance = new Mutex(true, "Local\\NeveNoWindows", out bool created);
        if (!created) return;
        System.Windows.Forms.Application.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var desktop = new DesktopController(app);
        app.Run();
    }
}
