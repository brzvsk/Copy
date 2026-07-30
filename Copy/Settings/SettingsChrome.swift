import SwiftUI

/// A colored rounded-square icon tile in the System Settings idiom: a white SF Symbol on a
/// filled rounded square. Used small in the sidebar rows and larger in each pane's hero.
struct SettingsSectionTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// The modest hero pinned above a pane's `Form`: the section's tile, its title, and a
/// one-line description. Utilitarian, not a marketing hero.
struct SettingsPaneHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 12) {
            SettingsSectionTile(systemImage: section.systemImage, color: section.tileColor, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 20, weight: .bold))
                Text(section.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 2)
    }
}
