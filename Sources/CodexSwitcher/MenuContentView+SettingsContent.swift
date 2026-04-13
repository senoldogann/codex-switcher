import SwiftUI

extension MenuContentView {

    var settingsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(
                    title: L("Görünüm", "Appearance"),
                    subtitle: L(
                        "Yazı boyutu, yazı ailesi ve vurgu renklerini buradan özelleştirin.",
                        "Customize text size, text family, and accent colors here."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsPickerRow(
                            title: L("Tema modu", "Theme mode"),
                            subtitle: L("Açık veya koyu görünüm seçin.", "Choose a light or dark appearance.")
                        ) {
                            segmentedButtons(
                                items: [
                                    (L("Koyu", "Dark"), "moon.fill"),
                                    (L("Açık", "Light"), "sun.max.fill")
                                ],
                                selectedIndex: isDarkMode ? 0 : 1,
                                action: { index in
                                    isDarkMode = index == 0
                                }
                            )
                        }

                        settingsPickerRow(
                            title: L("Yazı boyutu", "Text size"),
                            subtitle: L("Menü ve özet metinlerde uygulanır.", "Applied to menu and summary text.")
                        ) {
                            segmentedButtons(
                                items: AppearanceTextScale.allCases.map { ($0.title, "textformat.size") },
                                selectedIndex: AppearanceTextScale.allCases.firstIndex(of: appearance.textScale) ?? 1,
                                action: { index in
                                    appearanceTextScaleRaw = AppearanceTextScale.allCases[index].rawValue
                                }
                            )
                        }

                        settingsPickerRow(
                            title: L("Yazı ailesi", "Text family"),
                            subtitle: L("Arayüzün temel tipografisini değiştirir.", "Changes the primary interface typography.")
                        ) {
                            segmentedButtons(
                                items: AppearanceFontFamily.allCases.map { ($0.title, "textformat") },
                                selectedIndex: AppearanceFontFamily.allCases.firstIndex(of: appearance.fontFamily) ?? 0,
                                action: { index in
                                    appearanceFontFamilyRaw = AppearanceFontFamily.allCases[index].rawValue
                                }
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Tema rengi", "Theme color"))
                                .font(appearance.font(size: 11, weight: .semibold))
                                .foregroundStyle(gw.opacity(0.75))

                            Text(L(
                                "Aktif göstergeler ve seçili yüzeyler bu vurgu rengini kullanır.",
                                "Active indicators and selected surfaces use this accent color."
                            ))
                            .font(appearance.font(size: 10))
                            .foregroundStyle(gw.opacity(0.36))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                                ForEach(AppearanceThemePreset.allCases, id: \.rawValue) { preset in
                                    Button {
                                        appearanceThemePresetRaw = preset.rawValue
                                    } label: {
                                        VStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [preset.accentColor, preset.accentSecondaryColor],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(height: 36)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(
                                                            appearance.themePreset == preset
                                                                ? gw.opacity(0.82)
                                                                : gw.opacity(0.08),
                                                            lineWidth: appearance.themePreset == preset ? 1.4 : 1
                                                        )
                                                )

                                            Text(preset.title)
                                                .font(appearance.font(size: 9, weight: .medium))
                                                .foregroundStyle(gw.opacity(0.62))
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(appearance.themePreset == preset ? appearance.selectionFill : gw.opacity(0.03))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .pointerCursor()
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                isDarkMode = true
                                appearanceTextScaleRaw = AppearanceTextScale.medium.rawValue
                                appearanceFontFamilyRaw = AppearanceFontFamily.system.rawValue
                                appearanceThemePresetRaw = AppearanceThemePreset.emerald.rawValue
                            } label: {
                                Text(L("Varsayılana dön", "Reset defaults"))
                                    .font(appearance.font(size: 10, weight: .medium))
                                    .foregroundStyle(gw.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                        }
                    }
                }

                settingsSection(
                    title: L("Önizleme", "Preview"),
                    subtitle: L("Değişikliklerin menü içinde nasıl görüneceğini anında gösterir.", "Shows how changes look inside the menu immediately.")
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(appearance.accentColor)
                                .frame(width: 8, height: 8)
                            Text("Account 99")
                                .font(appearance.font(size: 13, weight: .semibold))
                                .foregroundStyle(gw.opacity(0.92))
                            Spacer()
                            Text("92%")
                                .font(appearance.monospacedFont(size: 10, weight: .semibold))
                                .foregroundStyle(gw.opacity(0.5))
                        }

                        Text("erkanc0233@icloud.com")
                            .font(appearance.monospacedFont(size: 10))
                            .foregroundStyle(gw.opacity(0.38))

                        HStack(spacing: 6) {
                            Text(Str.weekly)
                                .font(appearance.font(size: 9, weight: .medium))
                                .foregroundStyle(gw.opacity(0.34))
                                .frame(width: 42, alignment: .leading)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(gw.opacity(0.06))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [appearance.accentColor.opacity(0.9), appearance.accentSecondaryColor.opacity(0.6)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * 0.72)
                                }
                            }
                            .frame(height: 4)
                            Text("72%")
                                .font(appearance.monospacedFont(size: 9))
                                .foregroundStyle(gw.opacity(0.45))
                        }
                        .frame(height: 16)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(gw.opacity(0.04))
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func settingsSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(appearance.font(size: 13, weight: .semibold))
                .foregroundStyle(gw.opacity(0.82))

            Text(subtitle)
                .font(appearance.font(size: 10))
                .foregroundStyle(gw.opacity(0.34))

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(gw.opacity(0.03))
        )
    }

    private func settingsPickerRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(appearance.font(size: 11, weight: .semibold))
                .foregroundStyle(gw.opacity(0.74))

            Text(subtitle)
                .font(appearance.font(size: 10))
                .foregroundStyle(gw.opacity(0.32))

            content()
        }
    }

    private func segmentedButtons(
        items: [(title: String, icon: String)],
        selectedIndex: Int,
        action: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    action(index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(appearance.font(size: 10, weight: .medium))
                        Text(item.title)
                            .font(appearance.font(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedIndex == index ? gw.opacity(0.9) : gw.opacity(0.48))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedIndex == index ? appearance.selectionFill : gw.opacity(0.03))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
    }
}
