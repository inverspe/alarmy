import Foundation

/// Saves the whole app state as one JSON file.
public final class StateStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Missing file → defaults. Unreadable file → moved aside as
    /// `state.corrupt-<unix>.json` (kept for inspection), then defaults.
    public func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
        if let state = try? JSONDecoder().decode(AppState.self, from: data) { return state }
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        return AppState()
    }

    public func save(_ state: AppState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
