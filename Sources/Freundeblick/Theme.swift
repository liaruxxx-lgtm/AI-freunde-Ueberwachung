import SwiftUI

enum AppTheme {
    static let plum = Color(red: 0.34, green: 0.16, blue: 0.40)
    static let berry = Color(red: 0.72, green: 0.25, blue: 0.38)
    static let coral = Color(red: 0.93, green: 0.48, blue: 0.38)
    static let apricot = Color(red: 0.98, green: 0.75, blue: 0.48)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary

    static let heroGradient = LinearGradient(
        colors: [plum, berry, coral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [apricot.opacity(0.9), coral.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct SurfaceCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
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
    var tint: Color = AppTheme.plum

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
