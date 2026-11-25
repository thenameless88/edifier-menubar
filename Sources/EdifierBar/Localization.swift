import Foundation

/// UI language, chosen in the panel. English is the default.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", hungarian = "hu"
    var id: String { rawValue }
    var displayName: String { self == .english ? "English" : "Magyar" }
}

/// A message available in both UI languages.
struct Text2: Equatable {
    let en: String
    let hu: String
    init(_ en: String, _ hu: String) { self.en = en; self.hu = hu }
    init(verbatim s: String) { en = s; hu = s }
    func callAsFunction(_ lang: AppLanguage) -> String { lang == .english ? en : hu }
}
