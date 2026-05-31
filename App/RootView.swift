import SwiftUI

/// App root. Owns the single `GroomStore` instance and injects it into the
/// environment so every screen reads it via `@EnvironmentObject var store`.
struct RootView: View {
    @StateObject private var store = GroomStore()

    var body: some View {
        Group {
            if store.settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(store)
        .tint(.teal)
    }
}

#Preview {
    RootView()
}
