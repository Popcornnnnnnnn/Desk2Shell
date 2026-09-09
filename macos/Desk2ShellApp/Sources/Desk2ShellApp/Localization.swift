import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans
    case english

    static let defaultsKey = "appLanguage"

    static var preferred: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let language = AppLanguage(rawValue: saved) {
            return language
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .zhHans : .english
    }

    var id: String { rawValue }

    func text(_ chinese: String, _ english: String) -> String {
        self == .zhHans ? chinese : english
    }
}

struct BilingualText {
    let chinese: String
    let english: String
    let isSuccess: Bool

    init(_ chinese: String, _ english: String, isSuccess: Bool = false) {
        self.chinese = chinese
        self.english = english
        self.isSuccess = isSuccess
    }

    func value(for language: AppLanguage) -> String {
        language.text(chinese, english)
    }
}
