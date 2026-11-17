namespace Neve.Core;

public enum WindDirection { Vertical, Lateral }

public sealed record SnowSettings
{
    public double Density { get; init; } = 0.65;
    public double Speed { get; init; } = 0.75;
    public double Wind { get; init; } = 0.65;
    public WindDirection Direction { get; init; } = WindDirection.Vertical;
    public double MaxDepth { get; init; } = 24;
    public bool Accumulation { get; init; } = true;
    public bool Snowman { get; init; } = true;
    public bool AutomaticPlough { get; init; } = true;
    public SnowSettings Normalize() => this with
    {
        Density = Limit(Density, 0.15, 1.5, 0.65), Speed = Limit(Speed, 0.1, 2, 0.75),
        Wind = Limit(Wind, -1.5, 1.5, 0.65), MaxDepth = Limit(MaxDepth, 8, 45, 24),
        Direction = Enum.IsDefined(Direction) ? Direction : WindDirection.Vertical
    };
    private static double Limit(double v, double min, double max, double fallback) =>
        double.IsFinite(v) ? Math.Clamp(v, min, max) : fallback;
}

public readonly record struct Box(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y) && double.IsFinite(Width) &&
        double.IsFinite(Height) && Width > 0 && Height > 0;
}
public readonly record struct Span(double Lower, double Upper)
{
    public bool Contains(double x) => x >= Lower && x <= Upper;
}
public readonly record struct WindowGeometry(long Id, Box Bounds);
public struct Flake
{
    public double X, Y, VerticalSpeed, Drift, Radius, Opacity, Phase, Life;
    public bool Debris;
}
public sealed class Surface(long id, Box bounds, List<Span> spans, double[] depths)
{
    public long Id { get; } = id;
    public Box Bounds { get; } = bounds;
    public List<Span> Spans { get; } = spans;
    public double[] Depths { get; } = depths;
    public double Spacing => Bounds.Width / (Depths.Length - 1);
    public bool Contains(double x) => Spans.Exists(s => s.Contains(x));
    public double Depth(double x)
    {
        double t = Math.Clamp((x - Bounds.X) / Spacing, 0, Depths.Length - 1);
        int i = (int)t, j = Math.Min(i + 1, Depths.Length - 1);
        return Depths[i] * (1 - (t - i)) + Depths[j] * (t - i);
    }
    public double Top(double x) => Bounds.Y - Depth(x);
    public double Capacity(double x, double max)
    {
        double local = Math.Clamp(x - Bounds.X, 0, Bounds.Width), phase = (Id % 997) * 0.37;
        double Noise(double scale, double salt)
        {
            double t = local / scale + phase + salt, cell = Math.Floor(t), f = t - cell;
            double Hash(double v) { double n = Math.Sin(v * 127.1 + phase * 19.19) * 43758.5453; return n - Math.Floor(n); }
            double blend = f * f * (3 - 2 * f);
            return Hash(cell) * (1 - blend) + Hash(cell + 1) * blend;
        }
        double edge = Math.Min(local, Bounds.Width - local);
        double taper = Id == SnowModel.GroundId ? 1 : Math.Min(1, 0.12 + edge / 16);
        return max * (0.42 + 0.35 * Noise(66, 0) + 0.17 * Noise(23, 7) + 0.06 * Noise(8, 13)) * taper;
    }
}
public sealed class Plough(long surfaceId, double localX, Span route, double scale)
{
    public long SurfaceId { get; } = surfaceId;
    public double LocalX { get; set; } = localX;
    public Span Route { get; } = route;
    public double Scale { get; } = scale;
}

public sealed class SnowModel
{
    public const long GroundId = -1;
    public const int MaximumFlakes = 1800;
    public const int MaximumSurfaceSamples = 2048;
    public const int MaximumWindows = 64;
    public const int MaximumPloughs = 128;
    public double Width { get; }
    public double Height { get; }
    private SnowSettings settings = new();
    public SnowSettings Settings { get => settings; set => settings = value.Normalize(); }
    public List<Surface> Surfaces { get; private set; } = [];
    public List<Flake> Flakes { get; } = new(MaximumFlakes);
    public List<Plough> Ploughs { get; } = [];
    public double Time { get; private set; }
    public int GeometryVersion { get; private set; }
    private readonly Random random;
    private double nextPlough = 14;

    public SnowModel(double width, double height, SnowSettings? settings = null, int seed = 2026)
    {
        if (!double.IsFinite(width) || !double.IsFinite(height) || width < 1 || height < 1 || width > 100_000 || height > 100_000)
            throw new ArgumentOutOfRangeException(nameof(width));
        Width = width; Height = height; random = new(seed); Settings = settings ?? new();
        UpdateWindows([]); Replenish(true, 1);
    }

    public static List<Span> ExposedTop(WindowGeometry window, IEnumerable<WindowGeometry> inFront, double width)
    {
        List<Span> spans = [new(Math.Max(0, window.Bounds.X), Math.Min(width, window.Bounds.Right))];
        foreach (var front in inFront)
        {
            if (front.Bounds.Y > window.Bounds.Y + 1 || front.Bounds.Bottom <= window.Bounds.Y) continue;
            List<Span> remaining = [];
            foreach (var span in spans)
            {
                if (front.Bounds.Right <= span.Lower || front.Bounds.X >= span.Upper) { remaining.Add(span); continue; }
                if (front.Bounds.X > span.Lower) remaining.Add(new(span.Lower, front.Bounds.X));
                if (front.Bounds.Right < span.Upper) remaining.Add(new(front.Bounds.Right, span.Upper));
            }
            spans = remaining;
        }
        return spans.FindAll(s => s.Upper - s.Lower > 3);
    }

    // The caller supplies windows in foreground-to-background order, in monitor-local DIPs.
    public void UpdateWindows(IReadOnlyList<WindowGeometry> windows)
    {
        var previous = Surfaces.ToDictionary(s => s.Id);
        bool changed = false;
        List<Surface> next = [];
        HashSet<long> ids = [];
        for (int index = 0; index < Math.Min(windows.Count, MaximumWindows); index++)
        {
            var window = windows[index]; var rect = window.Bounds;
            if (window.Id == GroundId || !ids.Add(window.Id) || !rect.IsValid || rect.Y < 3 || rect.Y > Height - 10) continue;
            var spans = ExposedTop(window, windows.Take(index), Width);
            if (spans.Count == 0) continue;
            int count = Math.Max(2, (int)Math.Min(MaximumSurfaceSamples - 1, rect.Width / 4) + 1);
            previous.TryGetValue(window.Id, out var old);
            double[] depths = old is not null && old.Bounds.Width == rect.Width ? old.Depths : new double[count];
            var surface = new Surface(window.Id, rect, spans, depths);
            changed |= old is null || old.Bounds != rect || !old.Spans.SequenceEqual(spans);
            if (old is not null && !ReferenceEquals(depths, old.Depths))
                for (int i = 0; i < count; i++) depths[i] = old.Depth(old.Bounds.X + i * surface.Spacing);
            next.Add(surface);
        }
        next.Add(previous.GetValueOrDefault(GroundId) ?? new Surface(GroundId,
            new(0, Height - 1, Width, 1), [new(0, Width)], new double[Math.Max(2, Math.Min(MaximumSurfaceSamples, (int)(Width / 4) + 1))]));
        foreach (var old in Surfaces)
            if (old.Id != GroundId && !next.Exists(s => s.Id == old.Id)) { Scatter(old); changed = true; }
        Surfaces = next.OrderBy(s => s.Bounds.Y).ToList();
        if (changed) GeometryVersion++;
        Ploughs.RemoveAll(p => !Surfaces.Exists(s => s.Id == p.SurfaceId));
    }

    private Flake Fresh(bool initial) => new()
    {
        X = random.NextDouble() * Width, Y = initial ? random.NextDouble() * Height : -3 - random.NextDouble() * 42,
        VerticalSpeed = 22 + random.NextDouble() * 58, Drift = -8 + random.NextDouble() * 16,
        Radius = 0.7 + random.NextDouble() * 2.1, Opacity = 0.3 + random.NextDouble() * 0.65,
        Phase = random.NextDouble() * Math.PI * 2, Life = 3
    };
    private void Replenish(bool initial, double quality)
    {
        int target = (int)Math.Clamp(Width * Height / 2400 * Settings.Density * quality, 30, 1300);
        int count = Flakes.Count(f => !f.Debris);
        if (count < target) for (int i = count; i < target && Flakes.Count < MaximumFlakes; i++) Flakes.Add(Fresh(initial));
        else if (count > target)
        {
            int remove = count - target;
            Flakes.RemoveAll(f => !f.Debris && remove-- > 0);
        }
    }
    public void Step(double elapsed, double quality = 1)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0) return;
        double dt = Math.Min(elapsed, 0.05); Time += dt;
        Replenish(false, double.IsFinite(quality) ? Math.Clamp(quality, 0.25, 1) : 1);
        for (int i = 0; i < Flakes.Count; i++)
        {
            var f = Flakes[i]; double oldY = f.Y;
            if (f.Debris)
            {
                f.VerticalSpeed += 260 * dt; f.Drift *= Math.Pow(0.6, dt);
                f.X += f.Drift * dt; f.Y += f.VerticalSpeed * dt; f.Life -= dt;
            }
            else
            {
                double sway = Settings.Direction == WindDirection.Vertical ? 0.2 : 1;
                f.X += ((Settings.Direction == WindDirection.Lateral ? Settings.Wind * 65 : 0) +
                    (f.Drift + Math.Sin(Time * 0.8 + f.Phase) * 15) * sway) * dt;
                f.Y += f.VerticalSpeed * (0.4 + Settings.Speed) * dt;
            }
            if (f.X < -20) f.X = Width + 10;
            if (f.X > Width + 20) f.X = -10;
            Surface? hit = null;
            if (Settings.Accumulation && f.Y >= oldY)
                foreach (var surface in Surfaces)
                    if (surface.Contains(f.X) && oldY <= surface.Top(f.X) - f.Radius + 1 && f.Y >= surface.Top(f.X) - f.Radius)
                    { hit = surface; break; }
            if (hit is not null)
            {
                Deposit(hit, f.X, f.Radius * 0.75);
                if (f.Debris) f.Life = -1; else f = Fresh(false);
            }
            else if (f.Y > Height + 15) { if (f.Debris) f.Life = -1; else f = Fresh(false); }
            Flakes[i] = f;
        }
        Flakes.RemoveAll(f => f.Debris && f.Life <= 0);
        if (Settings.AutomaticPlough && Time >= nextPlough && Ploughs.Count == 0) StartAllPloughs();
        StepPloughs(dt);
    }
    private void Deposit(Surface surface, double x, double amount)
    {
        int center = (int)((x - surface.Bounds.X) / surface.Spacing);
        double max = Settings.MaxDepth * (surface.Id == GroundId ? 1.7 : 1);
        for (int offset = -3; offset <= 3; offset++)
        {
            int cell = center + offset;
            if (cell < 0 || cell >= surface.Depths.Length) continue;
            double cellX = surface.Bounds.X + cell * surface.Spacing;
            surface.Depths[cell] = Math.Min(surface.Capacity(cellX, max), surface.Depths[cell] + amount * Math.Exp(-offset * offset / 4.5) * 0.4);
        }
    }
    private void Scatter(Surface surface)
    {
        if (!Settings.Accumulation) return;
        for (int i = 0; i < surface.Depths.Length && Flakes.Count < MaximumFlakes; i += 3)
        {
            double x = surface.Bounds.X + i * surface.Spacing;
            if (surface.Depths[i] <= 0.8 || !surface.Contains(x)) continue;
            Flakes.Add(new Flake { X = x, Y = surface.Top(x), Drift = random.NextDouble() * 90 - 45,
                VerticalSpeed = -10 - random.NextDouble() * 55, Radius = 2, Opacity = 0.9, Life = 3, Debris = true });
        }
    }
    public bool StartPlough(long surfaceId = GroundId)
    {
        var surface = Surfaces.Find(s => s.Id == surfaceId);
        if (surface is null) return false;
        var routes = surface.Spans.FindAll(s => s.Upper - s.Lower >= 70);
        if (routes.Count == 0) return false;
        Ploughs.RemoveAll(p => p.SurfaceId == surfaceId);
        double scale = surfaceId == GroundId ? 1 : 0.72;
        foreach (var route in routes.Take(Math.Max(0, MaximumPloughs - Ploughs.Count)))
            Ploughs.Add(new(surfaceId, route.Lower - surface.Bounds.X - 45 * scale,
                new(route.Lower - surface.Bounds.X, route.Upper - surface.Bounds.X), scale));
        nextPlough = Time + 85; return true;
    }
    public void StartAllPloughs() { foreach (var id in Surfaces.Select(s => s.Id).ToArray()) StartPlough(id); }
    private void StepPloughs(double dt)
    {
        foreach (var p in Ploughs)
        {
            var surface = Surfaces.Find(s => s.Id == p.SurfaceId);
            if (surface is null) continue;
            double before = p.LocalX + 31 * p.Scale;
            p.LocalX += (p.SurfaceId == GroundId ? 84 : 100) * dt;
            double blade = p.LocalX + 31 * p.Scale;
            for (int i = 0; i < surface.Depths.Length; i++)
            {
                double x = i * surface.Spacing;
                if (x >= before - 14 * p.Scale && x <= blade + 14 * p.Scale && surface.Contains(surface.Bounds.X + x)) surface.Depths[i] = 0;
            }
        }
        Ploughs.RemoveAll(p => p.LocalX > p.Route.Upper + 50 * p.Scale);
    }
    public void Seed(double depth)
    {
        foreach (var s in Surfaces)
            for (int i = 0; i < s.Depths.Length; i++) s.Depths[i] = s.Capacity(s.Bounds.X + i * s.Spacing, Math.Min(depth, Settings.MaxDepth));
    }
    public void Clear()
    {
        foreach (var s in Surfaces) Array.Clear(s.Depths);
        Flakes.RemoveAll(f => f.Debris); Ploughs.Clear();
    }
}
