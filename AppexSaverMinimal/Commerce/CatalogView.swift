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

    @State private var hoveredId: String?

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
        .task {
            await model.load()
            await downloader.firstRunSetupIfNeeded(catalogSamples: model.loops.filter { $0.isSample })
            onLibraryChanged()
        }
    }

    @ViewBuilder private func card(_ loop: CatalogLoop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail(loop)
            Text(loop.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            actionRow(loop)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
    }

    @ViewBuilder private func thumbnail(_ loop: CatalogLoop) -> some View {
        let downloaded = downloader.isDownloaded(loop.id)
        CachedPoster(url: loop.poster.flatMap { URL(string: $0) })
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            // Animated preview on hover (streams a short clip from the site).
            if hoveredId == loop.id {
                LoopPreviewView(url: previewURL(loop))
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay(alignment: .topTrailing) { badge(loop).padding(6) }
        .overlay {
            if !loop.entitled && !loop.isSample {
                Image(systemName: "lock.fill").font(.title3).foregroundStyle(.white).shadow(radius: 4)
            } else if downloaded {
                // Play affordance for loops already in the library.
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 6)
                    .opacity(hoveredId == loop.id ? 0 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { inside in
            if inside { hoveredId = loop.id }
            else if hoveredId == loop.id { hoveredId = nil }
        }
        .onTapGesture {
            if downloaded, let url = downloader.localURL(for: loop.id) {
                FullScreenPlayer.play(url: url, title: loop.title)
            }
        }
        .help(downloaded ? "Click to play full screen" : "")
    }

    private func previewURL(_ loop: CatalogLoop) -> URL {
        CommerceAPI.baseURL.appendingPathComponent("media/previews/\(loop.id).mp4")
    }

    @ViewBuilder private func badge(_ loop: CatalogLoop) -> some View {
        if loop.isSample {
            tag("Starter", color: .green)
        } else if loop.entitled {
            tag("Owned", color: .blue)
        } else {
            tag(loop.tierTag.capitalized, color: .gray)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
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

/// Poster image cached in memory so catalog re-renders (e.g. when a download
/// finishes) don't re-fetch every poster and flash. Loads once per URL.
private enum PosterCache {
    static let shared = NSCache<NSURL, NSImage>()
}

struct CachedPoster: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = PosterCache.shared.object(forKey: url as NSURL) { image = cached; return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: data) else { return }
        PosterCache.shared.setObject(img, forKey: url as NSURL)
        image = img
    }
}
