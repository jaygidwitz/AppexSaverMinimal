//
//  LicenseView.swift
//  Surrealism · Commerce
//
//  Unlock panel / upsell. Reflects LicenseStore state: enter a key, show the
//  unlocked tier, or surface the device-limit / revoked states.
//

import SwiftUI

/// A brief horizontal shake — animate `travel` to a new integer to trigger one pass.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var amplitude: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = amplitude * sin(travel * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

struct LicenseView: View {
    @ObservedObject var store: LicenseStore
    @State private var keyInput = ""
    @State private var emailInput = ""
    @State private var shakeTrigger: CGFloat = 0
    @FocusState private var keyFocused: Bool
    @FocusState private var emailFocused: Bool

    private let storeURL = URL(string: "https://surrealism.app")!

    var body: some View {
        Group {
            switch store.state {
            case .unlocked(let tier, _):
                unlocked(tier: tier)
            case .checking:
                panel {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Checking your license…").foregroundStyle(.secondary)
                    }
                }
            case .deviceLimit:
                panel {
                    upsellHeader(title: "You've reached 3 devices",
                                 subtitle: "Deactivate another device to unlock this Mac.")
                    Button("Use a different key") { store.signOut() }.buttonStyle(GhostButtonStyle())
                }
            case .revoked:
                panel { entry(headline: "This license is no longer active",
                              sub: "Re-enter your key, or contact support if this is unexpected.") }
            case .locked:
                panel { entry(headline: "Unlock the full library",
                              sub: "All \(70) surreal loops — plus every new drop, forever.") }
            }
        }
    }

    // MARK: - Unlocked

    @ViewBuilder private func unlocked(tier: String) -> some View {
        panel(tint: true) {
            HStack(spacing: 12) {
                SurrealismMark(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full library unlocked").font(.system(size: 15, weight: .semibold))
                    Text(store.signedInEmail.map { "Signed in as \($0)" } ?? Self.tierLabel(tier))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign out") { store.signOut() }.buttonStyle(GhostButtonStyle())
            }
        }
    }

    // MARK: - Entry / upsell

    @ViewBuilder private func entry(headline: String, sub: String) -> some View {
        let hasError = store.entryError != nil
        upsellHeader(title: headline, subtitle: sub)

        // Primary path: sign in with email (magic link). Falls back to a pasted key.
        signInBlock()
        orDivider()

        HStack(spacing: 10) {
            TextField("SURR-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(borderColor(hasError: hasError), lineWidth: 1))
                )
                .frame(maxWidth: 300)
                .focused($keyFocused)
                .onSubmit(submit)
                // Clear the red state the moment they start correcting the key.
                .onChange(of: keyInput) { if store.entryError != nil { store.clearEntryError() } }
            Button("Unlock", action: submit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .modifier(ShakeEffect(travel: shakeTrigger))
        .onChange(of: store.entryError) {
            if store.entryError != nil {
                withAnimation(.linear(duration: 0.4)) { shakeTrigger += 1 }
            }
        }
        if let err = store.entryError {
            Text(Self.errorMessage(err))
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .frame(maxWidth: 300, alignment: .leading)
                .transition(.opacity)
        }
        Link(destination: storeURL) {
            HStack(spacing: 5) {
                Text("Don't have a key?").foregroundStyle(.secondary)
                Text("Get the full library →").foregroundStyle(.white).fontWeight(.medium)
            }.font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - Email sign-in

    @ViewBuilder private func signInBlock() -> some View {
        switch store.signIn {
        case .idle:
            HStack(spacing: 10) {
                TextField("you@email.com", text: $emailInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(emailFocused ? Color.accentColor : .white.opacity(0.12), lineWidth: 1))
                    )
                    .frame(maxWidth: 300)
                    .focused($emailFocused)
                    .onSubmit(sendLink)
                Button("Send sign-in link", action: sendLink)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!emailInput.contains("@"))
            }
        case .sendingLink, .exchanging:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(store.signIn == .exchanging ? "Signing you in…" : "Sending your link…")
                    .foregroundStyle(.secondary).font(.system(size: 13))
            }
        case .awaitingLink(let email):
            VStack(alignment: .leading, spacing: 6) {
                Text("Check your email").font(.system(size: 15, weight: .semibold))
                Text("We sent a sign-in link to \(email). Open it on this Mac to unlock.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Use a different email") { store.clearSignIn() }.buttonStyle(GhostButtonStyle())
            }
        case .linkExpired:
            VStack(alignment: .leading, spacing: 6) {
                Text("That link expired").font(.system(size: 15, weight: .semibold))
                Text("Sign-in links work once and expire quickly. Request a new one.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Try again") { store.clearSignIn() }.buttonStyle(PrimaryButtonStyle())
            }
        case .noLicense:
            VStack(alignment: .leading, spacing: 6) {
                Text("No active license on this account").font(.system(size: 15, weight: .semibold))
                Text("You're signed in, but this email has no active license.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Link("Get the full library", destination: storeURL).buttonStyle(PrimaryButtonStyle())
                    Button("Use a different email") { store.clearSignIn() }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func orDivider() -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            Text("or paste a key").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
        .frame(maxWidth: 300)
    }

    private func sendLink() {
        let email = emailInput
        Task { await store.signIn(email: email) }
    }

    @ViewBuilder private func upsellHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SurrealismMark(size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Chrome

    @ViewBuilder private func panel<Content: View>(tint: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05))
                    if tint {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.9).opacity(0.18), .clear],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }

    private func submit() {
        let key = keyInput
        Task { await store.enter(key: key) }
    }

    private func borderColor(hasError: Bool) -> Color {
        if hasError { return Color(red: 1.0, green: 0.42, blue: 0.42) }
        return keyFocused ? Color.accentColor : .white.opacity(0.12)
    }

    static func errorMessage(_ error: LicenseStore.EntryError) -> String {
        switch error {
        case .invalidKey:
            return "That key isn't valid — check for typos. It looks like SURR-XXXX-XXXX-XXXX."
        case .network:
            return "Couldn't reach Surrealism to verify. Check your connection and try again."
        }
    }

    static func tierLabel(_ tier: String) -> String {
        switch tier {
        case "lifetime-base": return "Founder's Lifetime"
        case "lifetime-everything": return "Lifetime Everything"
        case "plus-active": return "Surrealism Plus"
        case "pack": return "Pack owner"
        default: return tier
        }
    }
}
