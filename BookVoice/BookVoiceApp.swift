import SwiftUI

@main
struct BookVoiceApp: App {
    @StateObject private var library = BookLibrary()
    @StateObject private var player = BookSpeechPlayer()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(nil)
        }
    }
}
