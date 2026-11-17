import AppKit
import SwiftUI
import NeveCore
import NeveRendering

func makePreview(size: CGSize, settings: SnowSettings) -> SnowSimulation {
    var previewSettings = settings
    previewSettings.density = max(0.85, settings.density)
    let model = SnowSimulation(size: size, settings: previewSettings, seed: 107)
    model.updateWindows([
        WindowGeometry(id: 10, rect: CGRect(x: size.width * 0.52, y: size.height * 0.58, width: size.width * 0.4, height: size.height * 0.6)),
        WindowGeometry(id: 11, rect: CGRect(x: size.width * 0.08, y: size.height * 0.72, width: size.width * 0.57, height: size.height * 0.6))
    ])
    model.seedAccumulation(depth: 9)
    model.startPloughsOnWindows(includeGround: true)
    return model
}

struct SnowPreview: NSViewRepresentable {
    let settings: SnowSettings
    var running = true
    final class Coordinator {
        var timer: Timer?
        var running = true
        deinit { timer?.invalidate() }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SnowSceneView {
        let view = SnowSceneView(simulation: makePreview(size: CGSize(width: 536, height: 190), settings: settings), preview: true)
        let coordinator = context.coordinator
        coordinator.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak view, weak coordinator] _ in
            guard let view, coordinator?.running == true, view.window?.isVisible == true else { return }
            if abs(view.bounds.width - view.simulation.size.width) > 1 && view.bounds.width > 100 {
                view.simulation = makePreview(size: view.bounds.size, settings: view.simulation.settings)
            }
            view.simulation.step(1.0 / 30); view.presentFrame()
        }
        return view
    }
    func updateNSView(_ view: SnowSceneView, context: Context) {
        view.simulation.settings = settings
        context.coordinator.running = running
        view.setAnimationPaused(!running)
    }
    static func dismantleNSView(_ view: SnowSceneView, coordinator: Coordinator) { coordinator.timer?.invalidate() }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let plough: () -> Void
    let frontPlough: () -> Void
    let floorPlough: () -> Void
    let clear: () -> Void
    let close: () -> Void
    let quit: () -> Void

    private func setting(_ keyPath: WritableKeyPath<SnowSettings, Double>) -> Binding<Double> {
        Binding(get: { preferences.snow[keyPath: keyPath] }, set: { preferences.snow[keyPath: keyPath] = $0 })
    }
    private func flag(_ keyPath: WritableKeyPath<SnowSettings, Bool>) -> Binding<Bool> {
        Binding(get: { preferences.snow[keyPath: keyPath] }, set: { preferences.snow[keyPath: keyPath] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "snowflake").font(.system(size: 27, weight: .light)).foregroundStyle(.cyan)
                    .frame(width: 38, height: 38)
                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neve no Mac").font(.system(size: 17, weight: .semibold))
                    Text(preferences.running ? "Nevando sobre suas janelas" : "Efeito pausado")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Ativar neve", isOn: $preferences.running).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Ativar neve")
            }
            Divider().overlay(.white.opacity(0.04))
            VStack(spacing: 13) {
                control("Quantidade", value: setting(\.density), range: 0.15...1.5, label: "\(Int(preferences.snow.density * 100))%")
                control("Velocidade", value: setting(\.speed), range: 0.1...2, label: "\(Int(preferences.snow.speed * 100))%")
                HStack(spacing: 10) {
                    Text("Vento").font(.system(size: 11)).frame(width: 77, alignment: .leading)
                    Picker("Vento", selection: Binding(get: { preferences.snow.windDirection }, set: { direction in
                        var snow = preferences.snow
                        snow.windDirection = direction
                        if direction == .lateral && abs(snow.wind) < 0.08 { snow.wind = 0.65 }
                        preferences.snow = snow
                    })) {
                        Text("De cima para baixo").tag(SnowWindDirection.vertical)
                        Text("Lateral").tag(SnowWindDirection.lateral)
                    }.pickerStyle(.segmented).labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Acumular nas janelas", isOn: flag(\.accumulation))
                control("Profundidade", value: setting(\.maxDepth), range: 8...45, label: "\(Int(preferences.snow.maxDepth)) pt")
                    .disabled(!preferences.snow.accumulation)
            }
            .padding(12).background(card, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Boneco de neve", isOn: flag(\.showSnowman))
                Toggle("Tratores automáticos", isOn: flag(\.automaticPlough))
            }
            .padding(12).background(card, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Chamar o trator", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("LIMPA-NEVE").font(.system(size: 8, weight: .medium)).tracking(0.9).foregroundStyle(.cyan.opacity(0.8))
                }
                HStack(spacing: 8) {
                    Button(action: frontPlough) { Label("Nesta janela", systemImage: "macwindow").frame(maxWidth: .infinity) }
                        .help("Percorre e limpa a borda da janela que estava na frente.")
                    Button(action: plough) { Label("Em todas", systemImage: "square.on.square").frame(maxWidth: .infinity) }
                        .help("Envia tratores às janelas e à base da tela.")
                }
                HStack {
                    Button("Só na base da tela", action: floorPlough).buttonStyle(.borderless).foregroundStyle(.cyan)
                    Spacer()
                    Button("Limpar tudo", action: clear).buttonStyle(.borderless).foregroundStyle(.secondary)
                }.font(.system(size: 11))
            }
            .padding(12).background(card, in: RoundedRectangle(cornerRadius: 12))
            .disabled(!preferences.running)
            Divider()
            HStack {
                Text("Os cliques passam pela neve.").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Fechar", action: close).buttonStyle(.borderless)
                Button("Sair", action: quit).buttonStyle(.borderless).foregroundStyle(.secondary)
            }.font(.system(size: 11))
        }
        .toggleStyle(.switch).controlSize(.small).tint(.blue)
        .padding(18).frame(width: 380).fixedSize(horizontal: false, vertical: true).preferredColorScheme(.dark)
        .background(Color(red: 0.07, green: 0.1, blue: 0.15))
    }

    private var card: Color { Color(red: 0.09, green: 0.14, blue: 0.22) }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 11)).frame(width: 77, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 43, alignment: .trailing)
        }
    }
}
