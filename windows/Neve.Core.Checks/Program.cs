using Neve.Core;
using System.Text.Json;

int passed = 0;
void Check(string name, Action test) { test(); Console.WriteLine("PASS " + name); passed++; }
void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
WindowGeometry Window(long id, double x, double y, double width = 400, double height = 200) => new(id, new(x, y, width, height));
SnowModel Model(double width = 600, double height = 500) => new(width, height, new() { AutomaticPlough = false });

Check("occluded segments", () => {
    var spans = SnowModel.ExposedTop(Window(1, 0, 100), [Window(2, 120, 50, 140)], 400);
    Require(spans.SequenceEqual(new Span[] { new(0, 120), new(260, 400) }), "Covered section catches snow");
    Require(SnowModel.ExposedTop(Window(1, 0, 100), [Window(2, -10, 20, 500)], 400).Count == 0, "Fully covered roof is visible");
});
Check("movement preserves local snow and tractor", () => {
    var m = Model(); m.UpdateWindows([Window(1, 20, 150)]); m.Seed(16); m.StartPlough(1);
    var before = m.Surfaces.Single(s => s.Id == 1); var depths = before.Depths.ToArray();
    double tractor = m.Ploughs[0].LocalX;
    m.UpdateWindows([Window(1, 160, 210)]);
    var moved = m.Surfaces.Single(s => s.Id == 1);
    Require(moved.Bounds.X == 160 && moved.Bounds.Y == 210, "Geometry trails behind window");
    Require(moved.Depths.SequenceEqual(depths) && ReferenceEquals(before.Depths, moved.Depths), "Movement resampled or lost snow");
    Require(m.Ploughs[0].LocalX == tractor, "Tractor detached from local coordinates");
});
Check("resizing resamples bounded storage", () => {
    var m = Model(); m.UpdateWindows([Window(1, -10, 150, 1e100)]);
    Require(m.Surfaces.Single(s => s.Id == 1).Depths.Length <= SnowModel.MaximumSurfaceSamples, "Unbounded samples");
    m.Seed(12); m.UpdateWindows([Window(1, 10, 150, 300)]);
    Require(m.Surfaces.Single(s => s.Id == 1).Depths.Any(d => d > 0), "Resize discarded snow");
    m.UpdateWindows([Window(1, 10, 150, double.PositiveInfinity)]);
    Require(m.Surfaces.Count == 1, "Non-finite rectangle accepted");
});
Check("vertical mode ignores previous lateral wind", () => {
    var a = new SnowModel(1000, 800, new() { Accumulation = false, Wind = -1.5, Direction = WindDirection.Vertical }, 7);
    var b = new SnowModel(1000, 800, new() { Accumulation = false, Wind = 1.5, Direction = WindDirection.Vertical }, 7);
    a.Step(0.05); b.Step(0.05);
    Require(a.Flakes.Select(f => f.X).SequenceEqual(b.Flakes.Select(f => f.X)), "Vertical snow has lateral bias");
    b.Settings = b.Settings with { Direction = WindDirection.Lateral };
    var old = b.Flakes.ToArray(); b.Step(0.05);
    var visible = old.Zip(b.Flakes).Where(pair => pair.First.X < 800 && pair.First.Y < 700).ToArray();
    Require(visible.Length > 0 && visible.All(pair => pair.Second.X - pair.First.X > 3), "Lateral mode did not change motion");
});
Check("window tractor targets only its surface", () => {
    var m = Model(); m.UpdateWindows([Window(1, 0, 100), Window(2, 0, 300)]); m.Seed(20);
    double other = m.Surfaces.Single(s => s.Id == 2).Depths.Sum();
    double target = m.Surfaces.Single(s => s.Id == 1).Depths.Sum(); m.StartPlough(1);
    for (int i = 0; i < 240; i++) m.Step(1.0 / 30);
    Require(m.Surfaces.Single(s => s.Id == 1).Depths.Sum() < target * 0.3, "Target not cleared");
    Require(m.Surfaces.Single(s => s.Id == 2).Depths.Sum() >= other, "Another window was cleared");
    Require(m.Ploughs.Count == 0, "Finished tractor retained");
});
Check("tractor routes respect occlusion and close", () => {
    var m = Model(); m.UpdateWindows([Window(2, 150, 50, 120), Window(1, 0, 100, 420)]); m.StartPlough(1);
    Require(m.Ploughs.Count == 2, "Not one tractor per exposed route");
    Require(m.Ploughs.Select(p => p.Route).SequenceEqual(new Span[] { new(0, 150), new(270, 420) }), "Covered route not clipped");
    m.UpdateWindows([]); Require(m.Ploughs.Count == 0, "Closed window retained a tractor");
});
Check("saturated piles stay irregular and bounded", () => {
    var m = new SnowModel(420, 180, new() { AutomaticPlough = false, Density = 1.5, MaxDepth = 30 });
    m.UpdateWindows([Window(1, 0, 85, 420)]);
    for (int i = 0; i < 3000; i++) m.Step(1.0 / 30);
    var d = m.Surfaces.Single(s => s.Id == 1).Depths;
    var interior = d.Skip(8).SkipLast(8).ToArray();
    Require(interior.Max() - interior.Min() > 6, "Flat accumulation");
    Require(d[0] < interior.Max() * 0.3 && d.All(x => x >= 0 && x <= 30), "Invalid edge taper or depth");
});
Check("no accumulation still falls off screen", () => {
    var m = new SnowModel(400, 300, new() { Accumulation = false, Snowman = false });
    for (int i = 0; i < 900; i++) m.Step(1.0 / 30);
    Require(m.Surfaces.All(s => s.Depths.All(d => d == 0)), "Offscreen snow left a pile");
    Require(m.Flakes.All(f => f.Y <= 315), "Offscreen particles retained");
});
Check("window churn has bounded particles and surfaces", () => {
    var m = Model(3840, 2160);
    for (int cycle = 0; cycle < 30; cycle++)
    {
        m.UpdateWindows(Enumerable.Range(0, 150).Select(i => Window(cycle * 1000 + i, i * 20, 100 + i * 5)).ToArray());
        m.Seed(30); m.StartAllPloughs();
        Require(m.Surfaces.Count <= SnowModel.MaximumWindows + 1, "Unbounded surfaces");
        Require(m.Ploughs.Count <= SnowModel.MaximumPloughs, "Unbounded tractors");
        m.UpdateWindows([]);
        for (int i = 0; i < 100; i++) m.Step(1.0 / 30);
        Require(m.Flakes.Count <= SnowModel.MaximumFlakes, "Unbounded particles");
        m.Clear(); Require(m.Ploughs.Count == 0 && !m.Flakes.Any(f => f.Debris), "Cleanup retained objects");
    }
});
Check("invalid and missing settings are normalized", () => {
    var settings = new SnowSettings { Density = double.NaN, Speed = -20, Wind = 1e100, MaxDepth = double.PositiveInfinity, Direction = (WindDirection)99 }.Normalize();
    Require(settings.Density == 0.65 && settings.Speed == 0.1 && settings.Wind == 1.5 && settings.MaxDepth == 24, "Unsafe numeric settings");
    Require(settings.Direction == WindDirection.Vertical, "Unknown wind mode accepted");
    var minimal = JsonSerializer.Deserialize<SnowSettings>("{}")!.Normalize();
    Require(minimal.Direction == WindDirection.Vertical && minimal.Accumulation, "Defaults not restored");
    Require(JsonSerializer.Deserialize<SnowSettings>(JsonSerializer.Serialize(settings)) == settings, "Preferences roundtrip failed");
});
Console.WriteLine($"All {passed} core checks passed. Windows UI is not exercised by these checks.");
