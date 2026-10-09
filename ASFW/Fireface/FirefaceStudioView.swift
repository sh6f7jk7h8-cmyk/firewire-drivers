import SwiftUI

struct FirefaceStudioView: View {
    @StateObject private var control = FirefaceControlModel()
    @State private var section: Section = .mixer
    @State private var bank: Bank = .inputs

    private enum Section: String, CaseIterable, Identifiable {
        case mixer = "Микшер"
        case clock = "Клок"
        case diagnostics = "Диагностика"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .mixer: "slider.vertical.3"
            case .clock: "waveform.path.ecg"
            case .diagnostics: "stethoscope"
            }
        }
    }

    private enum Bank: String, CaseIterable, Identifiable {
        case inputs = "Входы"
        case playback = "Воспроизведение"
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 210)
            Divider()
            Group {
                switch section {
                case .mixer: mixer
                case .clock: clock
                case .diagnostics: ModernContentView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { control.start() }
    }

    private var mixer: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Text("При открытии показан сохранённый профиль карты. Изменения применяются к текущему микшеру.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Picker("Выход", selection: $control.selectedOutput) {
                    ForEach(0..<FirefaceMixerProtocol.channelCount, id: \.self) { channel in
                        Text("Выход \(channel + 1)").tag(channel)
                    }
                }
                .frame(width: 190)
                Picker("Источники", selection: $bank) {
                    ForEach(Bank.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 350)
                Spacer()
                Button("Обновить с карты") { control.refresh() }
                    .disabled(!control.connected || control.loading || control.applying)
            }
            if let error = control.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if control.loading { ProgressView("Чтение микшера…") }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(0..<FirefaceMixerProtocol.channelCount, id: \.self) { channel in
                        fader(channel: channel)
                    }
                }
            }
            .disabled(!control.mixerReady || control.applying)
            outputFader
        }
        .padding(24)
        .navigationTitle("Микшер")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(control.deviceName).font(.title2.bold())
                Text(control.connected ? "Драйвер подключён" : "Драйвер недоступен")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if control.applying { ProgressView() }
            Circle()
                .fill(control.mixerReady ? .green : .orange)
                .frame(width: 10, height: 10)
        }
    }

    private func fader(channel: Int) -> some View {
        let source: FirefaceMixerProtocol.Source = bank == .inputs ? .input(channel) : .playback(channel)
        let value = Binding<Double>(
            get: { bank == .inputs ? control.inputDecibels[channel] : control.playbackDecibels[channel] },
            set: { control.setDraft($0, source: source) }
        )
        return HStack(spacing: 16) {
            Text(bank == .inputs ? "Вход \(channel + 1)" : "Поток \(channel + 1)")
                .frame(width: 100, alignment: .leading)
            Slider(value: value, in: -90...6, onEditingChanged: { editing in
                if !editing { control.commit(source) }
            })
            Text(formatDB(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var outputFader: some View {
        let channel = control.selectedOutput
        let source: FirefaceMixerProtocol.Source = .output(channel)
        let value = Binding<Double>(
            get: { control.outputDecibels[channel] },
            set: { control.setDraft($0, source: source) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 16) {
                Text("Уровень выхода")
                    .fontWeight(.semibold)
                    .frame(width: 120, alignment: .leading)
                Slider(value: value, in: -90...6, onEditingChanged: { editing in
                    if !editing { control.commit(source) }
                })
                Text(formatDB(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)
            }
        }
        .disabled(!control.mixerReady || control.applying)
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Text("Источник клока").font(.headline)
            Text((control.clockStatus ?? 0) & 1 == 1 ? "Внутренний" : "Внешний")
                .font(.title3)
            Text("Частота потока задаётся драйвером. Текущая сборка поддерживает 48 кГц.")
                .foregroundStyle(.secondary)
            Button("Обновить") { control.refresh() }
                .disabled(!control.connected || control.loading)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Клок")
    }

    private func formatDB(_ value: Double) -> String {
        value <= -90 ? "−∞ dB" : String(format: "%.1f dB", value)
    }
}
