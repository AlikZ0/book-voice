import SwiftUI
import PDFKit

struct ReaderView: View {
    let bookID: UUID
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var player: BookSpeechPlayer
    @State private var document: PDFDocument?
    @State private var showSettings = false
    @State private var showPageJump = false
    @State private var pageInput = "1"

    private var book: Book? { library.books.first(where: { $0.id == bookID }) }
    private var page: Int { player.currentPage }

    var body: some View {
        VStack(spacing: 0) {
            if let document {
                VStack(spacing: 10) {
                    HStack {
                        Button {
                            pageInput = String(page + 1)
                            showPageJump = true
                        } label: {
                            Label("Страница \(page + 1) из \(max(player.pageCount, 1))", systemImage: "book.closed")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("\(Int(Double(page + 1) / Double(max(player.pageCount, 1)) * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                    ProgressView(value: Double(page + player.pageProgress), total: Double(max(player.pageCount, 1)))
                        .tint(.blue)
                        .padding(.horizontal, 20)

                    PDFPageViewer(document: document, pageIndex: page)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.primary.opacity(0.055))
                        }
                        .padding(.horizontal, 14)
                }
                .padding(.top, 14)
            } else {
                ContentUnavailableViewFallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if document != nil { playerPanel }
        }
        .navigationTitle(book?.title ?? "Книга")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(player)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPageJump) {
            NavigationStack {
                Form {
                    Section("Номер страницы") {
                        TextField("От 1 до \(player.pageCount)", text: $pageInput)
                            .keyboardType(.numberPad)
                    }
                    Section {
                        Button("Перейти") {
                            if let number = Int(pageInput), (1...max(1, player.pageCount)).contains(number) {
                                player.go(to: number - 1)
                                showPageJump = false
                            }
                        }
                        .disabled(Int(pageInput).map { !(1...max(1, player.pageCount)).contains($0) } ?? true)
                    }
                }
                .navigationTitle("Перейти к странице")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрыть") { showPageJump = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            guard let book else { return }
            document = PDFDocument(url: library.url(for: book))
            player.didChangePage = { [weak library] id, currentPage in
                library?.updatePosition(bookID: id, page: currentPage)
            }
            player.open(book: book, at: library.url(for: book))
        }
    }

    private var playerPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(Int(player.pageProgress * 100))% страницы")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 22) {
                Button { player.previousPage() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 48)
                }
                .disabled(page <= 0)
                .accessibilityLabel("Предыдущая страница")

                Button { player.playOrPause() } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.gradient)
                            .frame(width: 66, height: 66)
                            .shadow(color: .blue.opacity(0.22), radius: 12, y: 5)
                        if player.state == .loading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.state == .speaking ? "pause.fill" : "play.fill")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: player.state == .speaking ? 0 : 2)
                        }
                    }
                }
                .disabled(player.state == .loading)
                .accessibilityLabel(player.state == .speaking ? "Пауза" : "Слушать")

                Button { player.nextPage() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22))
                        .frame(width: 44, height: 48)
                }
                .disabled(page >= player.pageCount - 1)
                .accessibilityLabel("Следующая страница")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            HStack {
                Button { player.stop() } label: {
                    Label("Стоп", systemImage: "stop.fill")
                }
                .disabled(player.state == .stopped)

                Spacer()

                Button { showSettings = true } label: {
                    Label("Голос и скорость", systemImage: "waveform.circle")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if let notice = player.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 11)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.05)).frame(height: 1) }
    }

    private var statusText: String {
        switch player.state {
        case .stopped: return "Готов к чтению"
        case .loading: return "Получаем текст страницы…"
        case .speaking: return player.recognizedPage ? "Читаем распознанный текст" : "Сейчас читает"
        case .paused: return "Пауза"
        }
    }
}

private struct PDFPageViewer: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.backgroundColor = .secondarySystemGroupedBackground
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let desiredPage = document.page(at: pageIndex), view.currentPage !== desiredPage {
            view.go(to: desiredPage)
        }
    }
}

private struct ContentUnavailableViewFallback: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Не удалось открыть PDF")
                .font(.headline)
        }
    }
}
