import FamilyControls
import ManagedSettings

/// Optional extra protection: asks Screen Time to block deleting this app.
/// Needs the Family Controls entitlement, which TrollStore may or may not honour;
/// any failure is reported, never thrown into the UI.
enum AppRemovalGuard {
    @MainActor
    static func tryEnable() async -> Result<Void, Error> {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            ManagedSettingsStore().application.denyAppRemoval = true
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
