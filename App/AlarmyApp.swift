import SwiftUI
import UserNotifications

@main
struct AlarmyApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = DiagnosticsServices.shared
    }

    var body: some Scene {
        WindowGroup {
            DiagnosticsView()
        }
    }
}
