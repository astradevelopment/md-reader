import SwiftUI

/// Persisted reading preferences. Deliberately a singleton so that menu commands
/// can mutate it without the App scene observing (and therefore rebuilding) it.
@MainActor
final class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    static let minSize: Double = 13
    static let maxSize: Double = 26
    static let defaultSize: Double = 16

    private static let storageKey = "reader.fontSize"

    @Published var fontSize: Double {
        didSet {
            let clamped = min(max(fontSize, Self.minSize), Self.maxSize)
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            UserDefaults.standard.set(fontSize, forKey: Self.storageKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.storageKey)
        fontSize = stored > 0 ? min(max(stored, Self.minSize), Self.maxSize) : Self.defaultSize
    }

    var canIncrease: Bool { fontSize < Self.maxSize }
    var canDecrease: Bool { fontSize > Self.minSize }

    func increase() { fontSize = min(Self.maxSize, fontSize + 1) }
    func decrease() { fontSize = max(Self.minSize, fontSize - 1) }
    func reset() { fontSize = Self.defaultSize }
}
