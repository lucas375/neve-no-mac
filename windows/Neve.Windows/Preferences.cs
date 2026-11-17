using System.Text.Json;
using Neve.Core;

namespace Neve.Windows;

internal static class Preferences
{
    private static readonly string DirectoryPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NeveNoWindows");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");
    internal static SnowSettings Load()
    {
        try
        {
            if (!File.Exists(FilePath) || new FileInfo(FilePath).Length > 65_536) return new();
            return (JsonSerializer.Deserialize<SnowSettings>(File.ReadAllText(FilePath)) ?? new()).Normalize();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    internal static bool Save(SnowSettings settings)
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            string temporary = Path.Combine(DirectoryPath, "settings.tmp");
            File.WriteAllText(temporary, JsonSerializer.Serialize(settings.Normalize()));
            File.Move(temporary, FilePath, true);
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
    }
}
