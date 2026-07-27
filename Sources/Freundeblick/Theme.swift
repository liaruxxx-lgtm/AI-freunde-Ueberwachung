import AppKit
import SwiftUI

enum AppTheme {
    static let plum = Color(red: 0.34, green: 0.16, blue: 0.40)
    static let berry = Color(red: 0.72, green: 0.25, blue: 0.38)
    static let coral = Color(red: 0.93, green: 0.48, blue: 0.38)
    static let plumText = adaptiveTextColor(
        light: NSColor(red: 0.27, green: 0.08, blue: 0.35, alpha: 1),
        dark: NSColor(red: 0.86, green: 0.70, blue: 0.96, alpha: 1)
    )
    static let berryText = adaptiveTextColor(
        light: NSColor(red: 0.50, green: 0.08, blue: 0.18, alpha: 1),
        dark: NSColor(red: 1.00, green: 0.69, blue: 0.76, alpha: 1)
    )
    static let coralText = adaptiveTextColor(
        light: NSColor(red: 0.54, green: 0.13, blue: 0.07, alpha: 1),
        dark: NSColor(red: 1.00, green: 0.72, blue: 0.63, alpha: 1)
    )
    static let blueText = adaptiveTextColor(
        light: NSColor(red: 0.04, green: 0.25, blue: 0.55, alpha: 1),
        dark: NSColor(red: 0.40, green: 0.76, blue: 1.00, alpha: 1)
    )
    static let orangeText = adaptiveTextColor(
        light: NSColor(red: 0.48, green: 0.22, blue: 0.02, alpha: 1),
        dark: NSColor(red: 1.00, green: 0.72, blue: 0.38, alpha: 1)
    )
    static let tealText = adaptiveTextColor(
        light: NSColor(red: 0.02, green: 0.36, blue: 0.34, alpha: 1),
        dark: NSColor(red: 0.38, green: 0.85, blue: 0.79, alpha: 1)
    )
    static let neutralText = adaptiveTextColor(
        light: NSColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1),
        dark: NSColor(red: 0.82, green: 0.82, blue: 0.86, alpha: 1)
    )
    static let apricot = Color(red: 0.98, green: 0.75, blue: 0.48)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary

    static let heroGradient = LinearGradient(
        colors: [
            plum,
            berry,
            Color(red: 0.72, green: 0.25, blue: 0.23),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [apricot.opacity(0.9), coral.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.050, blue: 0.068)
            : cream
    }

    private static func adaptiveTextColor(
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(
                    from: [.darkAqua, .aqua]
                )
                return match == .darkAqua ? dark : light
            }
        )
    }
}

struct SurfaceCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: AppTheme.plum.opacity(0.08), radius: 18, y: 8)
    }
}

extension View {
    func surfaceCard(padding: CGFloat = 18) -> some View {
        modifier(SurfaceCardModifier(padding: padding))
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = AppTheme.plumText

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

struct EmptyArtwork: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppTheme.heroGradient)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(28)
    }
}
