import Foundation
import PDFKit
import AVFoundation
import Combine

@MainActor
final class BookSpeechPlayer: NSObject, ObservableObject {
    enum State: Equatable { case stopped, loading, speaking, paused }

    @Published private(set) var state: State = .stopped
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var pageProgress: Double = 0
    @Published private(set) var notice: String?
    @Published private(set) var recognizedPage = false

    @Published var rate: Float = 0.5
    @Published var chosenVoiceID: String = "automatic"

    private let synthesizer = AVSpeechSynthesizer()
    private var document: PDFDocument?
    private var activeBookID: UUID?
    private var task: Task<Void, Never>?
    private var chunks: [String] = []
    private var chunkIndex = 0
    private var currentUtterance: AVSpeechUtterance?
    private var generation: UInt = 0

    var didChangePage: ((UUID, Int) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        let stored = UserDefaults.standard.float(forKey: "speechRate")
        rate = stored == 0 ? 0.5 : stored
        chosenVoiceID = UserDefaults.standard.string(forKey: "voiceID") ?? "automatic"
    }

    func open(book: Book, at url: URL) {
        if activeBookID == book.id { return }
        stop()
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            notice = "Не удалось открыть книгу"
            return
        }
        activeBookID = book.id
        document = pdf
        pageCount = pdf.pageCount
        currentPage = min(max(book.lastPage, 0), pdf.pageCount - 1)
        pageProgress = 0
        notice = nil
    }

    func isCurrentBook(_ id: UUID) -> Bool { activeBookID == id }

    func close() {
        stop()
        document = nil
        activeBookID = nil
        pageCount = 0
        currentPage = 0
        pageProgress = 0
    }

    func setRate(_ newValue: Float) {
        rate = newValue
        UserDefaults.standard.set(newValue, forKey: "speechRate")
    }

    func setVoice(_ id: String) {
        chosenVoiceID = id
        UserDefaults.standard.set(id, forKey: "voiceID")
    }

    func playOrPause() {
        switch state {
        case .speaking:
            if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
        case .paused:
            if synthesizer.continueSpeaking() { state = .speaking }
            else { startCurrentPage() }
        case .stopped, .loading:
            startCurrentPage()
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        currentUtterance = nil
        chunks.removeAll()
        chunkIndex = 0
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
        recognizedPage = false
    }

    func nextPage() { go(to: currentPage + 1) }
    func previousPage() { go(to: currentPage - 1) }

    func go(to page: Int) {
        guard document != nil, pageCount > 0 else { return }
        let target = min(max(page, 0), pageCount - 1)
        guard target != currentPage else { return }
        let wasPlaying = state == .speaking || state == .loading
        stop()
        currentPage = target
        pageProgress = 0
        notifyPosition()
        if wasPlaying { startCurrentPage() }
    }

    private func notifyPosition() {
        if let id = activeBookID { didChangePage?(id, currentPage) }
    }

    private func startCurrentPage() {
        guard let pdf = document,
              let id = activeBookID,
              let page = pdf.page(at: currentPage) else { return }

        generation &+= 1
        let token = generation
        task?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        chunks = []
        chunkIndex = 0
        pageProgress = 0
        notice = nil
        recognizedPage = false
        state = .loading

        let index = currentPage
        task = Task { [weak self] in
            let directText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let result = await PDFTextExtractor.text(on: page, bookID: id, pageIndex: index)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.recognizedPage = directText.isEmpty
            guard !result.isEmpty else {
                self.state = .stopped
                self.notice = "На странице \(index + 1) не найден текст. Попробуй следующую страницу."
                return
            }
            self.chunks = Self.splitIntoChunks(result)
            self.chunkIndex = 0
            self.speakChunk()
        }
    }

    private func speakChunk() {
        guard chunkIndex < chunks.count else {
            finishPage()
            return
        }
        let text = chunks[chunkIndex]
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.voice = resolveVoice(for: text)
        utterance.postUtteranceDelay = 0.06
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            notice = "Не удалось настроить звук: \(error.localizedDescription)"
        }
        currentUtterance = utterance
        state = .speaking
        synthesizer.speak(utterance)
    }

    private func finishPage() {
        currentUtterance = nil
        if currentPage + 1 < pageCount {
            currentPage += 1
            pageProgress = 0
            notifyPosition()
            startCurrentPage()
        } else {
            pageProgress = 1
            state = .stopped
            notice = "Книга закончилась"
        }
    }

    private func resolveVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if chosenVoiceID != "automatic", let selected = voices.first(where: { $0.identifier == chosenVoiceID }) {
            return selected
        }
        let language = Self.detectLanguage(text)
        return voices.first(where: { $0.language == language }) ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func detectLanguage(_ text: String) -> String {
        var armenian = 0, cyrillic = 0
        for scalar in text.unicodeScalars.prefix(1500) {
            if (0x0530...0x058F).contains(scalar.value) { armenian += 1 }
            if (0x0400...0x052F).contains(scalar.value) { cyrillic += 1 }
        }
        if armenian > cyrillic && armenian > 0 { return "hy-AM" }
        if cyrillic > 0 { return "ru-RU" }
        return "en-US"
    }

    private static func splitIntoChunks(_ source: String, maximum: Int = 850) -> [String] {
        let cleaned = source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        var result: [String] = []
        var chunk = ""
        for word in cleaned.split(separator: " ") {
            let token = String(word)
            if chunk.count + token.count + 1 > maximum && !chunk.isEmpty {
                result.append(chunk)
                chunk = token
            } else {
                chunk += chunk.isEmpty ? token : " " + token
            }
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            self.chunkIndex += 1
            self.pageProgress = Double(self.chunkIndex) / Double(max(1, self.chunks.count))
            self.speakChunk()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // A stop/skip invalidates the current utterance before cancellation is delivered.
    }
}
