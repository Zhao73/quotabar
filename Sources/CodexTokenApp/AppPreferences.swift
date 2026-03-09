import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    fileprivate var localizationCode: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var experimentalQuotaEnabled: Bool {
        didSet { defaults.set(experimentalQuotaEnabled, forKey: Keys.experimentalQuotaEnabled) }
    }

    @Published var experimentalQuotaCommand: String {
        didSet { defaults.set(experimentalQuotaCommand, forKey: Keys.experimentalQuotaCommand) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        if defaults.object(forKey: Keys.experimentalQuotaEnabled) == nil {
            self.experimentalQuotaEnabled = true
        } else {
            self.experimentalQuotaEnabled = defaults.bool(forKey: Keys.experimentalQuotaEnabled)
        }
        self.experimentalQuotaCommand = defaults.string(forKey: Keys.experimentalQuotaCommand) ?? ""
    }

    var locale: Locale {
        switch language {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    func string(_ key: String) -> String {
        let value = resolvedBundle.localizedString(forKey: key, value: key, table: nil)
        if value != key {
            return value
        }
        return englishBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private var resolvedBundle: Bundle {
        if let code = language.localizationCode {
            return bundle(for: code) ?? englishBundle
        }

        let preferred = Bundle.preferredLocalizations(
            from: ["zh-Hans", "en"],
            forPreferences: Locale.preferredLanguages
        )
        let systemCode = preferred.first ?? "en"
        return bundle(for: systemCode) ?? englishBundle
    }

    private var englishBundle: Bundle {
        bundle(for: "en") ?? .main
    }

    private func bundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return nil
        }
        return bundle
    }
}

private enum Keys {
    static let language = "codextoken.language"
    static let experimentalQuotaEnabled = "codextoken.experimentalQuotaEnabled"
    static let experimentalQuotaCommand = "codextoken.experimentalQuotaCommand"
}
