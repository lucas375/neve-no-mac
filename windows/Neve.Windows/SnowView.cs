using System.Windows;
using System.Windows.Media;
using Neve.Core;

namespace Neve.Windows;

internal sealed class SnowView(SnowModel model) : FrameworkElement
{
    private static readonly Brush Snow = Frozen(232, 243, 255), White = Frozen(255, 255, 255);
    private static readonly Brush Dark = Frozen(30, 50, 74), Blue = Frozen(150, 210, 240), Yellow = Frozen(255, 195, 48);
    private static readonly Brush Orange = Frozen(255, 155, 40), Red = Frozen(225, 46, 61);
    private static readonly Brush[] FlakeBrushes = Enumerable.Range(0, 8).Select(i =>
        (Brush)Frozen(255, 255, 255, (byte)(70 + i * 25))).ToArray();
    private readonly Dictionary<long, Geometry> piles = [];
    private double lastPaint = -1;
    private int geometryVersion = -1;
    private static SolidColorBrush Frozen(byte r, byte g, byte b, byte alpha = 255)
    {
        var brush = new SolidColorBrush(Color.FromArgb(alpha, r, g, b)); brush.Freeze(); return brush;
    }
    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context);
        if (model.Settings.Accumulation)
        {
            if (model.Time - lastPaint >= 0.08 || geometryVersion != model.GeometryVersion)
            {
                piles.Clear();
                foreach (var surface in model.Surfaces) piles[surface.Id] = Outline(surface);
                lastPaint = model.Time; geometryVersion = model.GeometryVersion;
            }
            foreach (var path in piles.Values) context.DrawGeometry(Snow, null, path);
        }
        foreach (var f in model.Flakes)
            context.DrawEllipse(FlakeBrushes[Math.Clamp((int)((f.Opacity - 0.25) * 10), 0, 7)], null, new(f.X, f.Y), f.Radius, f.Radius);
        if (model.Settings.Snowman) DrawSnowman(context);
        foreach (var plough in model.Ploughs)
        {
            var surface = model.Surfaces.Find(s => s.Id == plough.SurfaceId);
            if (surface is null) continue;
            var clip = new GeometryGroup();
            foreach (var span in surface.Spans) clip.Children.Add(new RectangleGeometry(new(span.Lower, surface.Bounds.Y - 60, span.Upper - span.Lower, 65)));
            context.PushClip(clip);
            context.PushTransform(new TranslateTransform(surface.Bounds.X + plough.LocalX, surface.Bounds.Y));
            context.PushTransform(new ScaleTransform(plough.Scale, plough.Scale));
            DrawPlough(context);
            context.Pop(); context.Pop(); context.Pop();
        }
    }
    internal void RefreshPiles() { lastPaint = -100; InvalidateVisual(); }
    private static Geometry Outline(Surface surface)
    {
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            foreach (var span in surface.Spans)
            {
                List<Point> points = [new(span.Lower, surface.Top(span.Lower))];
                for (int i = 0; i < surface.Depths.Length; i++)
                {
                    double x = surface.Bounds.X + i * surface.Spacing;
                    if (x > span.Lower && x < span.Upper) points.Add(new(x, surface.Bounds.Y - surface.Depths[i]));
                }
                points.Add(new(span.Upper, surface.Top(span.Upper)));
                path.BeginFigure(new(span.Lower, surface.Bounds.Y + 0.6), true, true);
                path.LineTo(points[0], true, false);
                for (int i = 0; i < points.Count - 1; i++)
                {
                    var p0 = points[Math.Max(0, i - 1)]; var p1 = points[i];
                    var p2 = points[i + 1]; var p3 = points[Math.Min(points.Count - 1, i + 2)];
                    path.BezierTo(new(p1.X + (p2.X - p0.X) / 6, p1.Y + (p2.Y - p0.Y) / 6),
                        new(p2.X - (p3.X - p1.X) / 6, p2.Y - (p3.Y - p1.Y) / 6), p2, true, false);
                }
                path.LineTo(new(span.Upper, surface.Bounds.Y + 0.6), true, false);
            }
        }
        geometry.Freeze(); return geometry;
    }
    private void DrawSnowman(DrawingContext context)
    {
        bool Fits(Surface s, Span p) => p.Upper - p.Lower > 120 && s.Top(p.Lower + (p.Upper - p.Lower) * 0.73) > 84;
        var surface = model.Surfaces.Find(s => s.Id != SnowModel.GroundId && s.Spans.Exists(p => Fits(s, p)));
        double x = model.Width * 0.82, y = model.Height - 3;
        if (surface is not null)
        {
            var span = surface.Spans.Find(p => Fits(surface, p));
            x = span.Lower + (span.Upper - span.Lower) * 0.73; y = surface.Top(x);
        }
        foreach (var sphere in new[] { (Offset: 16, Radius: 17), (Offset: 40, Radius: 13), (Offset: 60, Radius: 10) })
            context.DrawEllipse(White, null, new(x, y - sphere.Offset), sphere.Radius, sphere.Radius);
        foreach (var eye in new[] { new Point(x - 3, y - 62), new Point(x + 4, y - 62), new Point(x, y - 40), new Point(x, y - 33) })
            context.DrawEllipse(Dark, null, eye, 1.3, 1.3);
        var nose = new StreamGeometry();
        using (var g = nose.Open()) { g.BeginFigure(new(x, y - 59), true, true); g.LineTo(new(x + 12, y - 57), true, false); g.LineTo(new(x, y - 55), true, false); }
        context.DrawGeometry(Orange, null, nose);
        context.DrawRectangle(Red, null, new(x - 11, y - 52, 22, 5));
        context.DrawRectangle(Red, null, new(x + 4, y - 49, 5, 15));
        context.DrawRoundedRectangle(Red, null, new(x - 10, y - 75, 20, 9), 4, 4);
        context.DrawRectangle(White, null, new(x - 12, y - 69, 24, 4));
        context.DrawEllipse(White, null, new(x + 8, y - 77), 3.5, 3.5);
    }
    private static void DrawPlough(DrawingContext context)
    {
        context.DrawRoundedRectangle(Dark, null, new(-25, -12, 53, 12), 6, 6);
        for (int x = -18; x <= 20; x += 9) context.DrawEllipse(Blue, null, new(x, -5), 3.5, 3.5);
        context.DrawRoundedRectangle(Yellow, null, new(-25, -22, 49, 13), 3, 3);
        context.DrawRectangle(Yellow, null, new(-14, -37, 23, 19));
        context.DrawRectangle(Blue, null, new(-10, -33, 15, 12));
        context.DrawRectangle(White, null, new(-17, -39, 29, 3));
        context.DrawEllipse(Orange, null, new(-2, -42), 3, 2.5);
        var blade = new StreamGeometry();
        using (var g = blade.Open())
        {
            g.BeginFigure(new(25, -16), true, true); g.LineTo(new(39, -27), true, false);
            g.LineTo(new(39, -2), true, false); g.LineTo(new(25, -7), true, false);
        }
        context.DrawGeometry(Blue, null, blade);
    }
}
