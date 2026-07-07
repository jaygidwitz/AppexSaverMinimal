//
//  LicenseView.swift
//  Surrealism · Commerce
//
//  Compact unlock panel for the host app. Reflects LicenseStore state: enter a
//  key, show the unlocked tier, or surface the device-limit / revoked states.
//

import SwiftUI

struct LicenseView: View {
    @ObservedObject var store: LicenseStore
    @State private var keyInput = ""

    private let storeURL = URL(string: "https://surrealism.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .unlocked(let tier, _):
                unlocked(tier: tier)
            case .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking your license…").foregroundStyle(.secondary)
                }
            case .deviceLimit:
                message("You've activated the maximum of 3 devices.",
                        detail: "Deactivate another device to use this Mac.")
                signOutRow(label: "Use a different key")
            case .revoked:
                message("This license is no longer active.",
                        detail: "If this is unexpected, re-enter your key or contact support.")
                entryRow()
            case .locked:
                entryRow()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.10)))
    }

    // MARK: - States

    @ViewBuilder private func unlocked(tier: String) -> some View {
        HStack(spacing: 10) {
            SurrealismMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Full library unlocked").font(.system(size: 14, weight: .semibold))
                Text(Self.tierLabel(tier)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign out") { store.signOut() }.buttonStyle(GhostButtonStyle())
        }
    }

    @ViewBuilder private func entryRow() -> some View {
        Text("Unlock the full library").font(.system(size: 14, weight: .semibold))
        HStack(spacing: 8) {
            TextField("SURR-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: 240)
                .onSubmit(submit)
            Button("Unlock", action: submit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        Link("Buy a license →", destination: storeURL)
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }

    @ViewBuilder private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func signOutRow(label: String) -> some View {
        Button(label) { store.signOut() }.buttonStyle(GhostButtonStyle())
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
