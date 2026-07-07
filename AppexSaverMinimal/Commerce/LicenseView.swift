//
//  LicenseView.swift
//  Surrealism · Commerce
//
//  Unlock panel / upsell. Reflects LicenseStore state: enter a key, show the
//  unlocked tier, or surface the device-limit / revoked states.
//

import SwiftUI

struct LicenseView: View {
    @ObservedObject var store: LicenseStore
    @State private var keyInput = ""
    @FocusState private var keyFocused: Bool

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
                    Text(Self.tierLabel(tier)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign out") { store.signOut() }.buttonStyle(GhostButtonStyle())
            }
        }
    }

    // MARK: - Entry / upsell

    @ViewBuilder private func entry(headline: String, sub: String) -> some View {
        upsellHeader(title: headline, subtitle: sub)
        HStack(spacing: 10) {
            TextField("SURR-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(keyFocused ? Color.accentColor : .white.opacity(0.12), lineWidth: 1))
                )
                .frame(maxWidth: 300)
                .focused($keyFocused)
                .onSubmit(submit)
            Button("Unlock", action: submit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
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
