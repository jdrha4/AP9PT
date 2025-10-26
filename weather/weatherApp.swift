import SwiftUI

@main
struct weatherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Prevent the keyboard from pushing your UI upward globally
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}
