import Foundation

/// Small persistent event log (last 80 lines), shown on the Diagnostics screen so
/// device behaviour can be read back after the phone was locked.
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    @Published private(set) var lines: [String]
    private let key = "diagnosticLog"
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {
        lines = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)"
        DispatchQueue.main.async {
            self.lines = Array((self.lines + [line]).suffix(80))
            UserDefaults.standard.set(self.lines, forKey: self.key)
        }
    }

    func clear() {
        lines = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
