//
//  CatalogView.swift
//  Surrealism · Commerce
//
//  Browse the loop catalog: entitled loops are downloadable into the shared
//  cache; locked loops link to the store. Free samples are tagged.
//

import SwiftUI

struct CatalogView: View {
    @ObservedObject var model: CatalogModel
    @ObservedObject var downloader: LoopDownloader
    var onLibraryChanged: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 14)]
    private let storeURL = URL(string: "https://surrealism.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Catalog").font(.system(size: 16, weight: .semibold))
                if model.loading { ProgressView().controlSize(.small).padding(.leading, 4) }
                Spacer()
                Button("Refresh") { Task { await model.load() } }.buttonStyle(GhostButtonStyle())
            }
            if let err = model.loadError {
                Text(err).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.loops) { loop in card(loop) }
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder private func card(_ loop: CatalogLoop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
                .frame(height: 96)
                .overlay(alignment: .topTrailing) { badge(loop).padding(6) }
                .overlay { if !loop.entitled && !loop.isSample { Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.5)) } }
            Text(loop.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            actionRow(loop)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
    }

    @ViewBuilder private func badge(_ loop: CatalogLoop) -> some View {
        if loop.isSample {
            tag("Sample", color: .green)
        } else if loop.entitled {
            tag("Owned", color: .blue)
        } else {
            tag(loop.tierTag.capitalized, color: .gray)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
    }

    @ViewBuilder private func actionRow(_ loop: CatalogLoop) -> some View {
        if downloader.isDownloaded(loop.id) {
            HStack {
                Label("In library", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Spacer()
                Button("Remove") { downloader.remove(loop.id); onLibraryChanged() }
                    .buttonStyle(GhostButtonStyle())
            }
        } else if downloader.downloading.contains(loop.id) {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading…").font(.caption).foregroundStyle(.secondary) }
        } else if loop.entitled || loop.isSample {
            Button(loop.isSample && !loop.entitled ? "Download sample" : "Download") {
                Task { await downloader.download(loop); onLibraryChanged() }
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Link("Unlock →", destination: storeURL).font(.caption).foregroundStyle(.secondary)
        }
        if let e = downloader.errors[loop.id] { Text(e).font(.caption2).foregroundStyle(.orange) }
    }
}
