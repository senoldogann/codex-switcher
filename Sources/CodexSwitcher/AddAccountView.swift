import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject var store: AppStore
    @State private var aliasText = ""
    @FocusState private var aliasFocused: Bool

    @AppStorage("isDarkMode")  private var isDarkMode: Bool = true
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @Environment(\.colorScheme) private var scheme

    private var gw: Color { scheme == .dark ? .white : .black }

    var body: some View {
        ZStack {
            // Frosted glass background — aynı popover materyali
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            scheme == .dark
                ? Color.black.opacity(0.45).ignoresSafeArea()
                : Color.white.opacity(0.1).ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar

                Divider().background(gw.opacity(0.08))

                Group {
                    switch store.addingStep {
                    case .idle:          idleView
                    case .waitingLogin:  waitingView
                    case .confirmProfile: confirmView
                    case .done:          doneView
                    }
                }
                .padding(28)
                .animation(.easeInOut(duration: 0.2), value: store.addingStep)
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text(Str.addAccount)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(gw.opacity(0.85))
            Spacer()
            if store.addingStep != .idle {
                Button {
                    store.cancelAddAccount()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(gw.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Idle

    private var idleView: some View {
            VStack(spacing: 20) {
                iconCircle(systemName: "person.badge.plus", color: gw.opacity(0.12))

            VStack(spacing: 6) {
                Text(Str.newAccount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(Str.loginDesc)
                    .font(.system(size: 12))
                    .foregroundStyle(gw.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            if let error = store.addAccountErrorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            actionButtons(
                primary: (Str.start, "arrow.right", { store.beginAddAccount() }),
                secondary: (Str.cancel, { store.cancelAddAccount() })
            )
        }
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(gw.opacity(0.06))
                    .frame(width: 52, height: 52)
                ProgressView()
                    .tint(gw.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text(Str.loginWait)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(Str.waitDesc)
                    .font(.system(size: 12))
                    .foregroundStyle(gw.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 20) {
            iconCircle(systemName: "checkmark", color: Color.green.opacity(0.2))

            VStack(spacing: 6) {
                Text(Str.detected)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gw.opacity(0.9))

                Text(store.pendingProfileEmail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(gw.opacity(0.45))
            }

            // Alias input
            VStack(alignment: .leading, spacing: 6) {
                Text(Str.alias)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(gw.opacity(0.3))
                    .textCase(.uppercase)
                    .tracking(0.5)

                TextField(Str.aliasPlaceholder, text: $aliasText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(gw.opacity(0.85))
                    .focused($aliasFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(gw.opacity(0.06), in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(gw.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .frame(maxWidth: .infinity)

            actionButtons(
                primary: (Str.save, "checkmark", {
                    store.confirmPendingProfile(alias: aliasText.trimmingCharacters(in: .whitespaces))
                }),
                secondary: (Str.cancel, { store.cancelAddAccount() })
            )
        }
        .onAppear { aliasFocused = true }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            iconCircle(systemName: "checkmark.seal.fill", color: Color.green.opacity(0.2))

            Text(Str.added)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(gw.opacity(0.9))

            glassButton(Str.close, icon: "xmark") {
                store.closeAddAccountWindow()
            }
        }
    }

    // MARK: - Helpers

    private func iconCircle(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(gw.opacity(0.1), lineWidth: 0.5)
                )
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(gw.opacity(0.7))
        }
    }

    private func actionButtons(
        primary: (String, String, () -> Void),
        secondary: (String, () -> Void)
    ) -> some View {
        HStack(spacing: 8) {
            Button(secondary.0, action: secondary.1)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(gw.opacity(0.4))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(gw.opacity(0.05), in: .capsule)
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)

            glassButton(primary.0, icon: primary.1, action: primary.2)
                .keyboardShortcut(.return)
        }
    }

    private func glassButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gw.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(gw.opacity(0.1), in: .capsule)
                .overlay(
                    Capsule()
                        .stroke(gw.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
