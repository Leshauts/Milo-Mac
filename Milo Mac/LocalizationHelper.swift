import Foundation

/// Helper function for localized strings
/// Usage: L("key") instead of NSLocalizedString("key", comment: "")
func L(_ key: String, comment: String = "") -> String {
    return NSLocalizedString(key, comment: comment)
}

/// Helper function for localized strings with format arguments
/// Usage: L("key.with.param", 42, "text") for strings like "Value: %d, Name: %@"
func L(_ key: String, _ args: CVarArg..., comment: String = "") -> String {
    let format = NSLocalizedString(key, comment: comment)
    return String(format: format, arguments: args)
}

/// Extension for common localization patterns
extension String {
    /// Returns localized version of this string as a key
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    /// Returns localized version with format arguments
    func localized(_ args: CVarArg...) -> String {
        let format = NSLocalizedString(self, comment: "")
        return String(format: format, arguments: args)
    }
}

/// Utility to get current language
struct LocalizationInfo {
    static var currentLanguage: String {
        return Bundle.main.preferredLocalizations.first ?? "en"
    }
    
    static var isRightToLeft: Bool {
        return NSLocale.characterDirection(forLanguage: currentLanguage) == .rightToLeft
    }
}
