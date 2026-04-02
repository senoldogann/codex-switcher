import Foundation

extension Bundle {
    /// Locates the app's resource bundle correctly in both dev and signed .app contexts.
    ///
    /// - In a signed .app bundle: looks in `Contents/Resources/CodexSwitcher_CodexSwitcher.bundle`
    ///   (standard codesign-compatible location).
    /// - In development (swift run / swift build): falls back to SPM's Bundle.module lookup
    ///   which finds the bundle next to the executable.
    static var appResources: Bundle {
        // App bundle: Contents/Resources/ is the standard codesign-friendly location
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("CodexSwitcher_CodexSwitcher.bundle")
            if let b = Bundle(url: url) { return b }
        }
        // Development fallback (swift build output next to executable)
        return Bundle.module
    }
}
