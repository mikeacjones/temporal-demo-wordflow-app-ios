import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Haptics for the gameplay gestures. No-ops off iOS.
enum Haptics {
    #if canImport(UIKit) && os(iOS)
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()
    #endif

    static func prepare() {
        #if canImport(UIKit) && os(iOS)
        selection.prepare()
        impact.prepare()
        #endif
    }

    /// Fired as the finger crosses each new letter on the wheel.
    static func letterTouched() {
        #if canImport(UIKit) && os(iOS)
        selection.selectionChanged()
        #endif
    }

    static func tap() {
        #if canImport(UIKit) && os(iOS)
        impact.impactOccurred(intensity: 0.7)
        #endif
    }

    static func success() {
        #if canImport(UIKit) && os(iOS)
        notice.notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit) && os(iOS)
        notice.notificationOccurred(.warning)
        #endif
    }

    static func error() {
        #if canImport(UIKit) && os(iOS)
        notice.notificationOccurred(.error)
        #endif
    }
}
