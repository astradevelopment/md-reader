import SwiftUI

/// Persisted reading preferences. Deliberately a singleton so that menu commands
/// can mutate it without the App scene observing (and therefore rebuilding) it.
@MainActor
final class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    /// 100% renders at this size; everything else in the theme is relative to it.
    static let baseSize: Double = 16

    static let minPercent: Double = 70
    static let maxPercent: Double = 200
    static let defaultPercent: Double = 100
    private static let step: Double = 10

    private static let percentKey = "reader.scalePercent"
    private static let legacySizeKey = "reader.fontSize"

    @Published var percent: Double {
        didSet {
            let clamped = Self.clamp(percent)
            if clamped != percent {
                percent = clamped
                return
            }
            UserDefaults.standard.set(percent, forKey: Self.percentKey)
        }
    }

    var fontSize: Double { Self.baseSize * percent / 100 }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.percentKey) != nil {
            percent = Self.clamp(defaults.double(forKey: Self.percentKey))
        } else if defaults.object(forKey: Self.legacySizeKey) != nil {
            // Carry over the point size this setting used to be stored as.
            percent = Self.clamp(defaults.double(forKey: Self.legacySizeKey) / Self.baseSize * 100)
            defaults.removeObject(forKey: Self.legacySizeKey)
        } else {
            percent = Self.defaultPercent
        }
    }

    var canIncrease: Bool { percent < Self.maxPercent }
    var canDecrease: Bool { percent > Self.minPercent }

    func increase() { percent = min(Self.maxPercent, (percent / Self.step).rounded(.down) * Self.step + Self.step) }
    func decrease() { percent = max(Self.minPercent, (percent / Self.step).rounded(.up) * Self.step - Self.step) }
    func reset() { percent = Self.defaultPercent }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, minPercent), maxPercent)
    }
}
