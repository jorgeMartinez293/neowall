import Foundation
import Sparkle

/// Sparkle, configured from Info.plist: the feed, the public key every download
/// is verified against, and a check once a day. See docs/DISTRIBUTION.md.
final class Updater {
    static let shared = Updater()

    /// Nil outside an app bundle that carries a public key, such as `swift run`:
    /// Sparkle would answer a missing key with a modal error on every launch.
    private let controller: SPUStandardUpdaterController?

    var isConfigured: Bool { controller != nil }

    private init() {
        let key = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String ?? ""
        controller = key.isEmpty ? nil : SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Sparkle keeps this in the user defaults; the config file decides it.
    var automaticChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != newValue else { return }
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Shows Sparkle's window even when there is nothing new.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}
