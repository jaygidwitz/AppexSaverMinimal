//
//  ContentView.swift
//  AppexSaverMinimal  ·  Surrealism screensaver host app
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  Host app: manages the local loop library (the /Users/Shared cache the
//  screensaver reads), previews it live, and installs/activates the saver.
//  The license + download-from-surrealism.app flow lands here once the backend
//  exists; for now the library is managed locally via "Add Loops…".
//

import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

private let logger = AppexLog.logger("HostApp")
private let storeURL = URL(string: "https://surrealism.app")!

// MARK: - Library model

struct LibraryVideo: Identifiable {
    let url: URL
    let bytes: Int64
    var thumbnail: NSImage?
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var videos: [LibraryVideo] = []
    @Published var isBusy = false

    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.bytes } }
    var isEmpty: Bool { videos.isEmpty }

    func reload() {
        videos = VideoCache.videos().map { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            return LibraryVideo(url: url, bytes: size ?? 0, thumbnail: nil)
        }
        generateThumbnails()
    }

    private func generateThumbnails() {
        for v in videos where v.thumbnail == nil {
            let url = v.url
            Task.detached(priority: .utility) {
                let image = Self.thumbnail(for: url)
                await MainActor.run {
                    if let idx = self.videos.firstIndex(where: { $0.url == url }) {
                        self.videos[idx].thumbnail = image
                    }
                }
            }
        }
    }

    nonisolated static func thumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 270)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func addVideos(completion: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.prompt = "Add"
        panel.message = "Choose seamless video loops to use as your screensaver"
        guard panel.runModal() == .OK else { return }

        let picked = panel.urls
        isBusy = true
        Task.detached(priority: .userInitiated) {
            Self.ensureCacheDir()
            let base = URL(fileURLWithPath: VideoCache.directory, isDirectory: true)
            for src in picked {
                let dest = base.appendingPathComponent(src.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.copyItem(at: src, to: dest)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
                } catch {
                    logger.error("Copy failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            await MainActor.run {
                self.isBusy = false
                self.reload()
                completion()
            }
        }
    }

    func remove(_ video: LibraryVideo, completion: () -> Void) {
        try? FileManager.default.removeItem(at: video.url)
        reload()
        completion()
    }

    func revealInFinder() {
        Self.ensureCacheDir()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: VideoCache.directory)
    }

    nonisolated static func ensureCacheDir() {
        try? FileManager.default.createDirectory(
            atPath: VideoCache.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Main view

struct ContentView: View {
    @StateObject private var pluginManager = PluginManager()
    @StateObject private var library = LibraryViewModel()
    @State private var previewToken = 0

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                previewCard
                librarySection
                screensaverSection
                storeSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 660, minHeight: 720)
        .onAppear { library.reload() }
    }

    private func bumpPreview() { previewToken += 1 }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 34))
                .foregroundStyle(.purple, .indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("Surrealism")
                    .font(.system(size: 28, weight: .bold))
                Text("Video Screensaver")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Live preview

    private var previewCard: some View {
        PreviewViewRepresentable(reloadToken: previewToken)
            .frame(height: 264)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    // MARK: Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Loops")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                if !library.isEmpty {
                    Text("\(library.videos.count) · \(LibraryViewModel.formatted(library.totalBytes))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    library.addVideos { bumpPreview() }
                } label: {
                    Label("Add Loops…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isBusy)

                Button {
                    library.revealInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if library.isBusy {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
            }

            if library.isEmpty {
                emptyLibraryState
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(library.videos) { video in
                        libraryCell(video)
                    }
                }
            }
        }
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No loops yet")
                .font(.headline)
            Text("Add your own seamless loops, or unlock the full library at surrealism.app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
    }

    private func libraryCell(_ video: LibraryVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = video.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.black.opacity(0.6))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(role: .destructive) {
                    library.remove(video) { bumpPreview() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Remove this loop")
            }
            Text(video.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(LibraryViewModel.formatted(video.bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Screensaver controls

    private var screensaverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screensaver")
                .font(.title2).fontWeight(.semibold)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow(
                        on: pluginManager.isInstalled,
                        onText: pluginManager.installedVersion.map { "Installed (v\($0))" } ?? "Installed",
                        offText: "Not installed",
                        busy: pluginManager.isLoading
                    )
                    statusRow(
                        on: pluginManager.isActiveScreensaver,
                        onText: "Active screensaver",
                        offText: "Not the active screensaver",
                        busy: pluginManager.isCheckingScreensaver
                    )

                    if let error = pluginManager.lastError ?? pluginManager.screensaverError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    HStack(spacing: 10) {
                        if pluginManager.isInstalled {
                            Button("Uninstall") { uninstall() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Install Screensaver") { install() }
                                .buttonStyle(.borderedProminent)
                        }

                        if pluginManager.isInstalled && !pluginManager.isActiveScreensaver {
                            Button("Set as Screensaver") {
                                Task { await pluginManager.enableAsScreensaver() }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button("System Settings…") { openScreenSaverSettings() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                .padding(6)
            }
        }
    }

    private func statusRow(on: Bool, onText: String, offText: String, busy: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(on ? Color.green : Color.gray).frame(width: 9, height: 9)
            Text(on ? onText : offText)
                .foregroundStyle(on ? .primary : .secondary)
            if busy { ProgressView().scaleEffect(0.6) }
            Spacer()
        }
        .font(.callout)
    }

    // MARK: Store CTA

    private var storeSection: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get the full surrealism.app library")
                        .fontWeight(.semibold)
                    Text("Unlock a growing catalog of surreal loops. Coming soon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Visit surrealism.app") {
                    NSWorkspace.shared.open(storeURL)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(6)
        }
    }

    // MARK: Actions

    private func install() {
        do { try pluginManager.install() }
        catch { logger.error("Install failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func uninstall() {
        do { try pluginManager.uninstall() }
        catch { logger.error("Uninstall failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func openScreenSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
}
