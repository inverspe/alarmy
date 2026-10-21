import SwiftUI

@main
struct AlarmyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DiagnosticsView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.tick() }
        }
    }
}
