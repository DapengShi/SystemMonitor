import SwiftUI

enum Palette {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let backgroundSecondary = Color(red: 0.08, green: 0.10, blue: 0.18)
    static let panelBackground = Color(red: 0.11, green: 0.14, blue: 0.24)
    static let cardBackground = Color(red: 0.13, green: 0.16, blue: 0.27)
    static let border = Color.white.opacity(0.08)
    static let accentCyan = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let accentMagenta = Color(red: 0.78, green: 0.42, blue: 0.98)
    static let accentGreen = Color(red: 0.40, green: 0.89, blue: 0.60)
    static let accentOrange = Color(red: 1.00, green: 0.56, blue: 0.32)
    static let accentPurple = Color(red: 0.62, green: 0.39, blue: 0.89)
    static let rowEven = Color.white.opacity(0.02)
    static let rowOdd = Color.white.opacity(0.04)
    static let rowSelected = Color.white.opacity(0.16)
    static let gradientCPU = LinearGradient(colors: [Palette.accentCyan, Palette.accentMagenta], startPoint: .leading, endPoint: .trailing)
    static let gradientMemory = LinearGradient(colors: [Palette.accentGreen, Color(red: 0.24, green: 0.73, blue: 0.87)], startPoint: .leading, endPoint: .trailing)
    static let gradientNetworkDown = LinearGradient(colors: [Color(red: 0.50, green: 0.67, blue: 0.99), Palette.accentCyan], startPoint: .leading, endPoint: .trailing)
    static let gradientNetworkUp = LinearGradient(colors: [Palette.accentOrange, Color(red: 0.99, green: 0.30, blue: 0.36)], startPoint: .leading, endPoint: .trailing)
    static let gradientProcess = LinearGradient(colors: [Palette.accentMagenta, Palette.accentPurple], startPoint: .leading, endPoint: .trailing)
}
