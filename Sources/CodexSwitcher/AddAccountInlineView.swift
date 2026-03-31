import SwiftUI

/// Inline version of AddAccountView — fits inside the popover, no separate window.
struct AddAccountInlineView: View {
    @EnvironmentObject var store: AppStore
    @State private var aliasText = ""
    @FocusState private var aliasFocused: Bool

    @AppStorage("isDarkMode")  private var isDarkMode: Bool = true
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @Environment(\.colorScheme) private var scheme

    private var gw: Color { scheme == .dark ? .white : .black }

    var body: some View {
        Group {
            switch store.addingStep {
            case .idle:          idleView
            case .waitingLogin:  waitingView
            case .confirmProfile: confirmView
            case .done:          doneView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .animation(.easeInOut(duration: 0.2), value: store.addingStep)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 16) {
            iconCircle(systemName: "person.badge.plus", color: gw.opacity(0.12))

            VStack(spacing: 4) {
                Text(Str.newAccount)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(Str.loginDesc)
                    .font(.system(size: 11))
                    .foregroundStyle(gw.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            HStack(spacing: 8) {
                Button(Str.cancel) { store.cancelAddAccount() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gw.opacity(0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(gw.opacity(0.05), in: .capsule)
                    .buttonStyle(.plain)

                glassButton(Str.start, icon: "arrow.right") { store.beginAddAccount() }
            }
        }
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(gw.opacity(0.06))
                    .frame(width: 44, height: 44)
                ProgressView()
                    .tint(gw.opacity(0.6))
            }

            VStack(spacing: 4) {
                Text(Str.loginWait)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(Str.waitDesc)
                    .font(.system(size: 11))
                    .foregroundStyle(gw.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 16) {
            iconCircle(systemName: "checkmark", color: Color.green.opacity(0.2))

            VStack(spacing: 4) {
                Text(Str.detected)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(store.pendingProfileEmail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Str.alias)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(gw.opacity(0.3))
                    .textCase(.uppercase)
                    .tracking(0.5)

                TextField(Str.aliasPlaceholder, text: $aliasText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(gw.opacity(0.85))
                    .focused($aliasFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(gw.opacity(0.06), in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(gw.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button(Str.cancel) { store.cancelAddAccount() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gw.opacity(0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(gw.opacity(0.05), in: .capsule)
                    .buttonStyle(.plain)

                glassButton(Str.save, icon: "checkmark") {
                    store.confirmPendingProfile(alias: aliasText.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        .onAppear { aliasFocused = true }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            iconCircle(systemName: "checkmark.seal.fill", color: Color.green.opacity(0.2))

            Text(Str.added)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(gw.opacity(0.9))

            glassButton(Str.close, icon: "xmark") { store.closeAddAccountWindow() }
        }
    }

    // MARK: - Helpers

    private func iconCircle(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(gw.opacity(0.1), lineWidth: 0.5)
                )
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(gw.opacity(0.7))
        }
    }

    private func glassButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gw.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(gw.opacity(0.1), in: .capsule)
                .overlay(
                    Capsule()
                        .stroke(gw.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
