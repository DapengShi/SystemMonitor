import SwiftUI

@MainActor
final class DetailThemeController: ObservableObject {
    @Published private(set) var palette: DetailThemePalette
    @Published var mode: DetailAppearanceMode {
        didSet {
            guard mode != oldValue else { return }
            persist(mode)
            palette = Self.resolvePalette(for: mode, systemColorScheme: systemColorScheme)
        }
    }

    private let storage: UserDefaults
    private let storageKey = "detailAppearanceMode"
    private let persistsSelection: Bool
    private var systemColorScheme: ColorScheme?

    init(initialMode: DetailAppearanceMode,
         systemColorScheme: ColorScheme? = nil,
         storage: UserDefaults = .standard,
         persistsSelection: Bool = true) {
        self.mode = initialMode
        self.storage = storage
        self.persistsSelection = persistsSelection
        self.systemColorScheme = systemColorScheme
        self.palette = Self.resolvePalette(for: initialMode, systemColorScheme: systemColorScheme)
        persist(initialMode)
    }

    func update(mode newMode: DetailAppearanceMode, using colorScheme: ColorScheme?) {
        if let colorScheme {
            systemColorScheme = colorScheme
        }
        guard mode != newMode else {
            if newMode == .system {
                palette = Self.resolvePalette(for: newMode, systemColorScheme: systemColorScheme)
            }
            return
        }
        mode = newMode
    }

    func updateSystemColorScheme(_ newValue: ColorScheme) {
        systemColorScheme = newValue
        guard mode == .system else { return }
        palette = Self.resolvePalette(for: mode, systemColorScheme: newValue)
    }

    static func storedMode(from storage: UserDefaults = .standard) -> DetailAppearanceMode {
        if let rawValue = storage.string(forKey: "detailAppearanceMode"),
           let saved = DetailAppearanceMode(rawValue: rawValue) {
            return saved
        }
        return .system
    }

    private func persist(_ mode: DetailAppearanceMode) {
        guard persistsSelection else { return }
        storage.set(mode.rawValue, forKey: storageKey)
    }

    private static func resolvePalette(for mode: DetailAppearanceMode, systemColorScheme: ColorScheme?) -> DetailThemePalette {
        switch mode {
        case .day:
            return .day()
        case .night:
            return .night()
        case .system:
            switch systemColorScheme {
            case .some(.dark):
                return .night()
            case .some(.light):
                return .day()
            case .none:
                return .day()
            @unknown default:
                return .day()
            }
        }
    }
}

extension DetailThemeController {
    static func preview(mode: DetailAppearanceMode, colorScheme: ColorScheme) -> DetailThemeController {
        DetailThemeController(
            initialMode: mode,
            systemColorScheme: colorScheme,
            storage: UserDefaults(),
            persistsSelection: false
        )
    }
}
