import SwiftUI

/// Inline version of AddAccountView — fits inside the popover, no separate window.
/// Liquid glass style with animated step transitions.
struct AddAccountInlineView: View {
    @EnvironmentObject var store: AppStore
    @State private var aliasText = ""
    @FocusState private var aliasFocused: Bool
    @State private var pulsePhase: CGFloat = 0

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
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.addingStep)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulsePhase = 1
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(gw.opacity(0.04))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(gw.opacity(0.08), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(gw.opacity(0.6))
            }

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
        VStack(spacing: 14) {
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(gw.opacity(0.06), lineWidth: 2)
                    .frame(width: 52 + pulsePhase * 20, height: 52 + pulsePhase * 20)
                    .opacity(1 - pulsePhase * 0.8)

                // Inner glass circle
                Circle()
                    .fill(gw.opacity(0.06))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(gw.opacity(0.1), lineWidth: 0.5)
                    )

                // Animated browser icon
                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(gw.opacity(0.6))
                    .scaleEffect(1 + pulsePhase * 0.1)
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

            // Step indicator dots
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(gw.opacity(i == 0 ? 0.6 : 0.15))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.top, 4)

            // Cancel button
            Button(Str.cancel) { store.cancelAddAccount() }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(gw.opacity(0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(gw.opacity(0.05), in: .capsule)
                .buttonStyle(.plain)
                .pointerCursor()
                .padding(.top, 4)
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.8))
            }

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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.8))
            }

            Text(Str.added)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(gw.opacity(0.9))

            glassButton(Str.close, icon: "xmark") { store.closeAddAccountWindow() }
        }
    }

    // MARK: - Helpers

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
        .pointerCursor()
    }
}
