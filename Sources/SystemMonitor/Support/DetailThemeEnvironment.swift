import SwiftUI

private struct DetailThemeKey: EnvironmentKey {
    @MainActor
    static var defaultValue: DetailThemeController = DetailThemeController(
        initialMode: .system,
        systemColorScheme: nil,
        storage: UserDefaults(),
        persistsSelection: false
    )
}

extension EnvironmentValues {
    var detailTheme: DetailThemeController {
        get { self[DetailThemeKey.self] }
        set { self[DetailThemeKey.self] = newValue }
    }
}

extension View {
    func detailTheme(_ controller: DetailThemeController) -> some View {
        environment(\.detailTheme, controller)
    }
}
