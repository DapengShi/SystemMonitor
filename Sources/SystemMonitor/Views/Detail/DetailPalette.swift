// Copyright 2024 SystemMonitor Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

enum DetailAppearanceMode: String, CaseIterable, Identifiable {
    case day
    case night
    case system

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .day:
            return "Day"
        case .night:
            return "Night"
        case .system:
            return "System"
        }
    }

    var symbolName: String {
        switch self {
        case .day:
            return "sun.max"
        case .night:
            return "moon.stars"
        case .system:
            return "aqi.medium"
        }
    }
}

struct DetailThemePalette {
    struct Gradients {
        let cpu: LinearGradient
        let memory: LinearGradient
        let networkDown: LinearGradient
        let networkUp: LinearGradient
        let process: LinearGradient
    }

    let background: Color
    let backgroundSecondary: Color
    let panelBackground: Color
    let cardBackground: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let iconMuted: Color
    let accentPrimary: Color
    let accentSecondary: Color
    let accentTertiary: Color
    let accentQuaternary: Color
    let accentWarning: Color
    let accentSuccess: Color
    let rowEven: Color
    let rowOdd: Color
    let rowSelected: Color
    let controlBackground: Color
    let controlBorder: Color
    let shadow: Color
    let gradients: Gradients
    let paginationTint: Color
    let textOnAccent: Color

    static func day() -> DetailThemePalette {
        let accentPrimary = Color(red: 0.05, green: 0.52, blue: 0.94)
        let accentSecondary = Color(red: 0.63, green: 0.25, blue: 0.72)
        let accentTertiary = Color(red: 0.31, green: 0.67, blue: 0.48)
        let accentQuaternary = Color(red: 0.37, green: 0.40, blue: 0.82)
        let accentWarning = Color(red: 0.91, green: 0.37, blue: 0.21)
        let accentSuccess = Color(red: 0.18, green: 0.61, blue: 0.42)

        return DetailThemePalette(
            background: Color(red: 0.95, green: 0.97, blue: 1.0),
            backgroundSecondary: Color(red: 0.92, green: 0.94, blue: 0.99),
            panelBackground: Color.white,
            cardBackground: Color(red: 0.97, green: 0.98, blue: 1.0),
            border: Color.black.opacity(0.12),
            primaryText: Color(red: 0.07, green: 0.10, blue: 0.17),
            secondaryText: Color(red: 0.19, green: 0.24, blue: 0.34),
            tertiaryText: Color(red: 0.36, green: 0.41, blue: 0.53),
            iconMuted: Color(red: 0.48, green: 0.53, blue: 0.65),
            accentPrimary: accentPrimary,
            accentSecondary: accentSecondary,
            accentTertiary: accentTertiary,
            accentQuaternary: accentQuaternary,
            accentWarning: accentWarning,
            accentSuccess: accentSuccess,
            rowEven: Color.black.opacity(0.03),
            rowOdd: Color.black.opacity(0.05),
            rowSelected: accentPrimary.opacity(0.18),
            controlBackground: Color(red: 0.96, green: 0.97, blue: 1.0),
            controlBorder: Color.black.opacity(0.1),
            shadow: Color.black.opacity(0.16),
            gradients: Gradients(
                cpu: LinearGradient(colors: [accentPrimary, accentSecondary], startPoint: .leading, endPoint: .trailing),
                memory: LinearGradient(colors: [accentTertiary, Color(red: 0.12, green: 0.59, blue: 0.82)], startPoint: .leading, endPoint: .trailing),
                networkDown: LinearGradient(colors: [Color(red: 0.33, green: 0.49, blue: 0.94), accentPrimary], startPoint: .leading, endPoint: .trailing),
                networkUp: LinearGradient(colors: [accentWarning, Color(red: 0.96, green: 0.42, blue: 0.31)], startPoint: .leading, endPoint: .trailing),
                process: LinearGradient(colors: [accentSecondary, accentQuaternary], startPoint: .leading, endPoint: .trailing)
            ),
            paginationTint: accentPrimary,
            textOnAccent: Color.white
        )
    }

    static func night() -> DetailThemePalette {
        let accentPrimary = Color(red: 0.35, green: 0.78, blue: 0.98)
        let accentSecondary = Color(red: 0.78, green: 0.42, blue: 0.98)
        let accentTertiary = Color(red: 0.40, green: 0.89, blue: 0.60)
        let accentQuaternary = Color(red: 0.62, green: 0.39, blue: 0.89)
        let accentWarning = Color(red: 1.00, green: 0.56, blue: 0.32)
        let accentSuccess = Color(red: 0.24, green: 0.73, blue: 0.87)

        return DetailThemePalette(
            background: Color(red: 0.05, green: 0.07, blue: 0.12),
            backgroundSecondary: Color(red: 0.09, green: 0.11, blue: 0.19),
            panelBackground: Color(red: 0.14, green: 0.17, blue: 0.28),
            cardBackground: Color(red: 0.17, green: 0.20, blue: 0.33),
            border: Color.white.opacity(0.12),
            primaryText: Color.white.opacity(0.96),
            secondaryText: Color.white.opacity(0.82),
            tertiaryText: Color.white.opacity(0.68),
            iconMuted: Color.white.opacity(0.6),
            accentPrimary: accentPrimary,
            accentSecondary: accentSecondary,
            accentTertiary: accentTertiary,
            accentQuaternary: accentQuaternary,
            accentWarning: accentWarning,
            accentSuccess: accentSuccess,
            rowEven: Color.white.opacity(0.05),
            rowOdd: Color.white.opacity(0.08),
            rowSelected: Color.white.opacity(0.22),
            controlBackground: Color(red: 0.21, green: 0.23, blue: 0.34),
            controlBorder: Color.white.opacity(0.12),
            shadow: Color.black.opacity(0.5),
            gradients: Gradients(
                cpu: LinearGradient(colors: [accentPrimary, accentSecondary], startPoint: .leading, endPoint: .trailing),
                memory: LinearGradient(colors: [accentTertiary, accentSuccess], startPoint: .leading, endPoint: .trailing),
                networkDown: LinearGradient(colors: [Color(red: 0.50, green: 0.67, blue: 0.99), accentPrimary], startPoint: .leading, endPoint: .trailing),
                networkUp: LinearGradient(colors: [accentWarning, Color(red: 0.99, green: 0.30, blue: 0.36)], startPoint: .leading, endPoint: .trailing),
                process: LinearGradient(colors: [accentSecondary, accentQuaternary], startPoint: .leading, endPoint: .trailing)
            ),
            paginationTint: accentPrimary,
            textOnAccent: Color.white
        )
    }

    func rowBackground(isEven: Bool) -> Color {
        isEven ? rowEven : rowOdd
    }
}

struct DetailAppearanceSelection {
    let mode: DetailAppearanceMode
    let palette: DetailThemePalette
}
