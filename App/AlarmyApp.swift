import SwiftUI

@main
struct AlarmyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.tick() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.state.ringSession, session.phase != .finished {
            MorningFlowView()
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView {
            AlarmListView().tabItem { Label("Alarms", systemImage: "alarm") }
            ObjectsView().tabItem { Label("Objects", systemImage: "camera") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            DiagnosticsView().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .tint(Theme.sunlight)
    }
}
