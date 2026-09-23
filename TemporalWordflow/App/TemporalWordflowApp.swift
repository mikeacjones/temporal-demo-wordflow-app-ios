import SwiftUI

@main
struct TemporalWordflowApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Palette.uv)
                .preferredColorScheme(.light)
        }
    }
}
