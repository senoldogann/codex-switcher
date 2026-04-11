import SwiftUI
import AppKit

// MARK: - Side Rail

extension MenuContentView {

    var sideRail: some View {
        let langLabel: String = {
            switch appLanguage {
            case "tr": return "TR"
            case "en": return "EN"
            default:   return Str.langAuto
            }
        }()

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                railButton(
                    "rectangle.stack.person.crop",
                    L("Hesaplar", "Accounts"),
                    selected: screen == .main
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .main }
                }

                railDivider

                railButton(
                    "plus",
                    Str.addAccount,
                    selected: screen == .addAccount
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .addAccount }
                }
                .disabled(store.isAddingAccount)

                railDivider

                railButton(
                    "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    Str.history,
                    selected: screen == .history
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .history }
                }

                railDivider

                railButton("arrow.triangle.2.circlepath", Str.switchNow) {
                    store.switchToNext()
                }
                .disabled(store.profiles.count < 2)

                railDivider

                updateRailButton

                railDivider

                railButton(
                    "paintbrush.pointed",
                    L("Ayarlar", "Settings"),
                    selected: screen == .settings
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { screen = .settings }
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 10)

            VStack(spacing: 0) {
                railButton("globe", langLabel) {
                    if appLanguage == "system"   { appLanguage = "tr" }
                    else if appLanguage == "tr"  { appLanguage = "en" }
                    else                         { appLanguage = "system" }
                }

                railDivider

                railButton("eye", emailsBlurred ? Str.showEmail : Str.hideEmail) {
                    withAnimation(.easeInOut(duration: 0.2)) { emailsBlurred.toggle() }
                }

                railDivider

                railButton(
                    "dollarsign.circle",
                    budgetState.label,
                    foreground: budgetState.isExceeded ? .red.opacity(0.86) : nil
                ) {
                    showBudgetAlert()
                }

                railDivider

                railButton("arrow.counterclockwise", L("Sıfırla", "Reset")) {
                    store.resetStatistics()
                }

                railDivider

                railButton("power", Str.quit) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(width: 68)
    }

    // MARK: Rail Buttons

    var railDivider: some View {
        Divider()
            .background(gw.opacity(0.05))
            .padding(.horizontal, 14)
    }

    var updateRailButton: some View {
        Button {
            if store.availableUpdate != nil {
                store.openReleasePage()
            } else {
                store.checkForUpdatesManually()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                railButtonBody(
                    icon: "arrow.down.circle",
                    label: L("Güncelle", "Update"),
                    selected: false,
                    foreground: store.availableUpdate != nil ? Color.orange.opacity(0.85) : gw.opacity(0.46)
                )
                if store.availableUpdate != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .offset(x: -20, y: 10)
                }
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    func railButton(
        _ icon: String,
        _ label: String,
        selected: Bool = false,
        foreground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            railButtonBody(
                icon: icon,
                label: label,
                selected: selected,
                foreground: foreground ?? (selected ? gw.opacity(0.76) : gw.opacity(0.42))
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    func railButtonBody(icon: String, label: String, selected: Bool, foreground: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(appearance.font(size: 12, weight: selected ? .semibold : .medium))
            Text(label)
                .font(appearance.font(size: 7, weight: selected ? .semibold : .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .foregroundStyle(foreground)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? appearance.selectionFill : .clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    // MARK: Budget

    var budgetState: BudgetUsageState {
        let limit = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        let spent = store.costs.values.reduce(0, +)
        return BudgetUsageState.make(spent: spent, limit: limit)
    }

    func showBudgetAlert() {
        let alert = NSAlert()
        alert.messageText = L("Haftalık bütçe limiti", "Weekly budget limit (USD)")
        alert.informativeText = L("0 girerek devre dışı bırakın.", "Enter 0 to disable.")
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("İptal", "Cancel"))

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let current = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        tf.stringValue = current > 0 ? String(format: "%.2f", current) : ""
        tf.placeholderString = "0.00"
        tf.bezelStyle = .roundedBezel
        alert.accessoryView = tf

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let val = Double(tf.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 0
            UserDefaults.standard.set(max(0, val), forKey: "weeklyBudgetUSD")
            store.refreshTokenUsage()
        }
    }
}
