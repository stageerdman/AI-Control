import SwiftUI
import AIControlCore

@main
struct AIControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("AI Control")
            .font(.title)
            .padding()
            .frame(minWidth: 480, minHeight: 320)
    }
}
