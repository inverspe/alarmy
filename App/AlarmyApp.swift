import SwiftUI

@main
struct AlarmyApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("Alarmy").font(.largeTitle.bold())
                Text("Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
