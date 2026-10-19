using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace AllInOneIME.Settings;

/// <summary>
/// For the tests (<c>--screenshots DIR</c>): each section drawn into PNG files, the window as it shows (<c>NN-id-theme
/// .png</c>) and the whole section, scrolled or not (<c>NN-id-theme-full.png</c>), its lists open; then the app quits.
/// The XAML is rendered itself (RenderTargetBitmap), so nothing on the screen over the window gets in.
/// </summary>
static class Screenshots
{
    public static async Task TakeAsync(MainWindow window, string folder, string theme)
    {
        Directory.CreateDirectory(folder);
        await Task.Delay(500);
        var sections = window.Sections.ToList();
        for (var i = 0; i < sections.Count; i++)
        {
            window.SelectSection(sections[i].Id, expandAll: true);
            await Task.Delay(400);
            var name = $"{i + 1:00}-{sections[i].Id}-{theme}";
            await SaveAsync(window.RootElement, Path.Combine(folder, name + ".png"));
            await SaveAsync(window.PageElement, Path.Combine(folder, name + "-full.png"));
        }
        File.WriteAllText(Path.Combine(folder, $"done-{theme}.txt"), string.Join("\n", sections.Select(s => s.Id)));
        Application.Current.Exit();
    }

    static async Task SaveAsync(UIElement element, string path)
    {
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(element);
        var pixels = await bitmap.GetPixelsAsync();
        var file = await StorageFile.GetFileFromPathAsync(await Create(path));
        using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        var dpi = (float)(element.XamlRoot?.RasterizationScale ?? 1) * 96;
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight,
                             dpi, dpi, System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.ToArray(pixels));
        await encoder.FlushAsync();
    }

    static async Task<string> Create(string path)
    {
        await File.WriteAllBytesAsync(path, []);
        return path;
    }
}
