using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Neve.Core;

namespace Neve.Windows;

internal sealed class SettingsWindow : Window
{
    private readonly DesktopController desktop;
    private readonly TextBlock status = new() { FontSize = 11, Foreground = Brushes.LightSlateGray, TextWrapping = TextWrapping.Wrap };
    private static SolidColorBrush Color(byte r, byte g, byte b) => new(System.Windows.Media.Color.FromRgb(r, g, b));
    internal SettingsWindow(DesktopController controller)
    {
        desktop = controller;
        Title = "Neve no Windows"; Width = 390; SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Color(18, 26, 38); Foreground = Brushes.White; FontFamily = new("Segoe UI");
        var root = new StackPanel { Margin = new(20) };
        Content = root;
        root.Children.Add(new TextBlock { Text = "❄  Neve no Windows", FontSize = 23, FontWeight = FontWeights.SemiBold, Foreground = Color(88, 217, 249), Margin = new(0, 0, 0, 14) });
        var enabled = Check("Ativar neve", desktop.Running); enabled.Click += (_, _) => desktop.SetRunning(enabled.IsChecked == true); root.Children.Add(enabled);
        Slider(root, "Quantidade", 0.15, 1.5, desktop.Settings.Density, (s, v) => s with { Density = v });
        Slider(root, "Velocidade", 0.1, 2, desktop.Settings.Speed, (s, v) => s with { Speed = v });
        root.Children.Add(new TextBlock { Text = "Vento", Margin = new(0, 10, 0, 7) });
        var wind = new StackPanel { Orientation = Orientation.Horizontal };
        var vertical = new RadioButton { Content = "De cima para baixo", IsChecked = desktop.Settings.Direction == WindDirection.Vertical, Margin = new(0, 0, 16, 6), GroupName = "Wind" };
        var lateral = new RadioButton { Content = "Lateral", IsChecked = desktop.Settings.Direction == WindDirection.Lateral, GroupName = "Wind" };
        vertical.Checked += (_, _) => Save(desktop.Settings with { Direction = WindDirection.Vertical });
        lateral.Checked += (_, _) => Save(desktop.Settings with { Direction = WindDirection.Lateral });
        wind.Children.Add(vertical); wind.Children.Add(lateral); root.Children.Add(wind);
        Flag(root, "Acumular nas janelas", desktop.Settings.Accumulation, (s, v) => s with { Accumulation = v });
        Slider(root, "Profundidade", 8, 45, desktop.Settings.MaxDepth, (s, v) => s with { MaxDepth = v });
        Flag(root, "Boneco de neve", desktop.Settings.Snowman, (s, v) => s with { Snowman = v });
        Flag(root, "Tratores automáticos", desktop.Settings.AutomaticPlough, (s, v) => s with { AutomaticPlough = v });
        root.Children.Add(new TextBlock { Text = "CHAMAR O TRATOR", Foreground = Color(88, 217, 249), FontSize = 11, Margin = new(0, 16, 0, 8) });
        var buttons = new WrapPanel();
        AddButton(buttons, "Nesta janela", desktop.PloughFront);
        AddButton(buttons, "Em todas", desktop.PloughAll);
        AddButton(buttons, "Só na base", desktop.PloughGround);
        AddButton(buttons, "Limpar tudo", desktop.Clear);
        root.Children.Add(buttons);
        root.Children.Add(new TextBlock { Text = "Os cliques passam pela neve.", FontSize = 11, Foreground = Brushes.LightSlateGray, Margin = new(0, 12, 0, 6) });
        root.Children.Add(status);
        var footer = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right, Margin = new(0, 12, 0, 0) };
        AddButton(footer, "Fechar", Close); AddButton(footer, "Sair", desktop.Quit); root.Children.Add(footer);
    }
    private static CheckBox Check(string text, bool value) => new() { Content = text, IsChecked = value, Margin = new(0, 9, 0, 6), Foreground = Brushes.White };
    private void Flag(Panel panel, string text, bool value, Func<SnowSettings, bool, SnowSettings> change)
    {
        var check = Check(text, value); check.Click += (_, _) => Save(change(desktop.Settings, check.IsChecked == true)); panel.Children.Add(check);
    }
    private void Slider(Panel panel, string text, double min, double max, double value, Func<SnowSettings, double, SnowSettings> change)
    {
        var line = new DockPanel { Margin = new(0, 10, 0, 3) };
        var label = new TextBlock { Text = text }; line.Children.Add(label);
        var number = new TextBlock { Text = value.ToString("0.00"), HorizontalAlignment = HorizontalAlignment.Right, Foreground = Brushes.LightSlateGray };
        line.Children.Add(number); panel.Children.Add(line);
        var slider = new Slider { Minimum = min, Maximum = max, Value = value, Foreground = Color(88, 217, 249) };
        slider.ValueChanged += (_, _) => { number.Text = slider.Value.ToString("0.00"); Save(change(desktop.Settings, slider.Value)); };
        panel.Children.Add(slider);
    }
    private static void AddButton(Panel parent, string title, Action action)
    {
        var button = new Button { Content = title, Padding = new(10, 7, 10, 7), Margin = new(0, 0, 7, 7),
            Foreground = Color(88, 217, 249), Background = Color(24, 38, 58), BorderBrush = Color(40, 67, 87) };
        button.Click += (_, _) => action(); parent.Children.Add(button);
    }
    private void Save(SnowSettings settings) => status.Text = desktop.SetSettings(settings) ? "" : "Não foi possível salvar os ajustes neste computador.";
}
