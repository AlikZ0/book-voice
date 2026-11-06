import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var player: BookSpeechPlayer
    @Environment(\.dismiss) private var dismiss

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            $0.language == $1.language ? $0.name < $1.name : $0.language < $1.language
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Скорость чтения", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.2f", player.rate))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(player.rate) },
                            set: { player.setRate(Float($0)) }
                        ), in: 0.35...0.65, step: 0.025)
                        HStack {
                            Text("Медленнее")
                            Spacer()
                            Text("Быстрее")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Воспроизведение")
                } footer: {
                    Text("Изменения скорости и голоса применяются при начале следующей страницы. Для применения сразу нажми «Стоп», затем «Слушать».")
                }

                Section {
                    Picker("Голос", selection: Binding(
                        get: { player.chosenVoiceID },
                        set: { player.setVoice($0) }
                    )) {
                        Text("Автоматически по языку").tag("automatic")
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                } header: {
                    Text("Голос")
                } footer: {
                    Text("Показаны голоса, доступные на этом iPhone. Для русского, английского или армянского нужен установленный системный голос соответствующего языка.")
                }

                Section("Работа без интернета") {
                    Label("PDF хранится локально", systemImage: "iphone")
                    Label("Озвучивание через iOS", systemImage: "waveform")
                    Label("OCR от Apple для страниц-сканов", systemImage: "text.viewfinder")
                }
                .font(.subheadline)

                Section {
                    Text("BookVoice 1.0 · PDF Reader")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
