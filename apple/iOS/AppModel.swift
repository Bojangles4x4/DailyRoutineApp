import Foundation

@MainActor
final class AppModel: ObservableObject {
    let health = HealthKitService()
    let watch = PhoneWatchSessionManager()
}
