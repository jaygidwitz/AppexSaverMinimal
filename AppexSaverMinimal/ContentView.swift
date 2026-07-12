//
//  ContentView.swift
//  AppexSaverMinimal  ·  Surrealism screensaver host app
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  Host app: manages the local loop library (the /Users/Shared cache the
//  screensaver reads), previews it live, and installs/activates the saver.
//  Dark, immersive theme to match the surreal loops.
//

import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

private let logger = AppexLog.logger("HostApp")
private let storeURL = URL(string: "https://surrealism.app")!

// MARK: - Brand mark

/// Iridescent glossy orb echoing the metallic surreal loops.
struct SurrealismMark: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            // Glossy pearlescent sphere — matches the app icon's orb: a bright
            // top-left highlight fading to a deep violet edge for 3D depth.
            Circle().fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.99, green: 0.97, blue: 1.00),  // near-white core
                        Color(red: 0.87, green: 0.83, blue: 0.98),  // soft lavender
                        Color(red: 0.55, green: 0.45, blue: 0.85),  // violet
                        Color(red: 0.22, green: 0.17, blue: 0.40),  // deep edge
                    ],
                    center: UnitPoint(x: 0.37, y: 0.31),
                    startRadius: 0, endRadius: size * 0.60))
            // Iridescent wash — pink toward the top, cyan toward the bottom.
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.55, blue: 0.86).opacity(0.38), // pink
                        .clear,
                        Color(red: 0.42, green: 0.86, blue: 0.96).opacity(0.42), // cyan
                    ],
                    startPoint: .topTrailing, endPoint: .bottomLeading))
                .blendMode(.screen)
            // Specular highlight (the glossy dot).
            Ellipse().fill(
                RadialGradient(colors: [.white.opacity(0.95), .clear],
                               center: .center, startRadius: 0, endRadius: size * 0.16))
                .frame(width: size * 0.34, height: size * 0.26)
                .offset(x: -size * 0.17, y: -size * 0.20)
            // Rim: bright top edge, darker bottom edge, for a rounded read.
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.28)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: max(1, size * 0.02))
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.40, green: 0.20, blue: 0.70).opacity(0.45), radius: size * 0.18, y: size * 0.06)
    }
}

// MARK: - Button styles

/// Clean white capsule — the brand's primary action. Restraint on the buttons;
/// the iridescence lives only in the orb/wordmark.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.05, green: 0.03, blue: 0.10))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet glass capsule for secondary actions.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Library model

struct LibraryVideo: Identifiable {
    let url: URL
    let bytes: Int64
    var thumbnail: NSImage?
    var id: URL { url }

    /// Friendly name: bare numeric filenames become "Loop 3".
    var displayName: String {
        let n = url.deletingPathExtension().lastPathComponent
        return n.allSatisfy(\.isNumber) && !n.isEmpty ? "Loop \(n)" : n
    }
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
        gen.maximumSize = CGSize(width: 640, height: 360)
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
            await MainActor.run { self.isBusy = false; self.reload(); completion() }
        }
    }

    func remove(_ video: LibraryVideo, completion: () -> Void) {
        try? FileManager.default.removeItem(at: video.url)
        reload()
        completion()
    }

    nonisolated static func ensureCacheDir() {
        try? FileManager.default.createDirectory(
            atPath: VideoCache.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Main view

struct ContentView: View {
    @StateObject private var pluginManager = PluginManager()
    @StateObject private var library = LibraryViewModel()
    // Shared, app-owned: the magic-link callback (handled in AppDelegate) must
    // update the same store this window's sign-in UI is bound to.
    @EnvironmentObject private var license: LicenseStore
    @EnvironmentObject private var playback: PlaybackSettings
    @StateObject private var catalog = CatalogModel()
    @StateObject private var downloader = LoopDownloader()
    @State private var previewToken = 0

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    private let backdrop = LinearGradient(
        colors: [Color(red: 0.09, green: 0.05, blue: 0.17), Color(red: 0.02, green: 0.02, blue: 0.05)],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 28) {
                        screensaverSection
                        librarySection
                        LicenseView(store: license)
                        CatalogView(model: catalog, downloader: downloader,
                                    onLibraryChanged: { library.reload() })
                        storeSection
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .frame(minWidth: 680, minHeight: 760)
        .preferredColorScheme(.dark)
        .navigationTitle("Surrealism")
        .onAppear { library.reload() }
        .task { await license.revalidateIfNeeded() }
        // Magic-link return (surrealism://auth/callback) is handled app-level in
        // AppDelegate — not per-window here, which would spawn a second window.
    }

    private func bumpPreview() { previewToken += 1 }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
            )
    }

    // MARK: Hero (full-bleed cover video)

    private var hero: some View {
        PreviewViewRepresentable(reloadToken: previewToken)
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
                    .frame(height: 160)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 13) {
                    SurrealismMark(size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Surrealism")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Video Screensaver")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(28)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if !library.videos.isEmpty {
                    Button {
                        let active = RotationResolver.activeURLs(
                            rotation: playback.rotation,
                            library: library.videos.map(\.url))
                        FullScreenPlayer.playPlaylist(urls: active, title: "Surrealism",
                                                      shuffle: playback.shuffle,
                                                      crossFade: playback.crossFadeSeconds)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play all")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(28)
                    .help("Play the whole library full screen")
                }
            }
            .clipped()
    }

    // MARK: Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Loops").font(.title2).fontWeight(.semibold)
                Spacer()
                if !library.isEmpty {
                    Text("\(library.videos.count) loops · \(LibraryViewModel.formatted(library.totalBytes))")
                        .font(.callout).foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 10) {
                Button { library.addVideos { bumpPreview() } } label: {
                    Label("Add Loops…", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(library.isBusy)
                if library.isBusy { ProgressView().scaleEffect(0.7) }
                Spacer()
            }

            if library.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.videos) { cell($0) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            SurrealismMark(size: 44)
            Text("No loops yet").font(.headline)
            Text("Add your own seamless loops, or unlock the full library at surrealism.app.")
                .font(.callout).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private func cell(_ video: LibraryVideo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = video.thumbnail {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.white.opacity(0.06))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }
                }
                .frame(height: 124).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
                .overlay(alignment: .center) {
                    Image(systemName: "play.circle.fill").font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.9)).shadow(radius: 5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { FullScreenPlayer.play(url: video.url, title: video.displayName) }
                .help("Click to play full screen")

                Button(role: .destructive) {
                    library.remove(video) { bumpPreview() }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain).padding(8).help("Remove this loop")
            }
            Text(video.displayName).font(.callout.weight(.medium)).lineLimit(1)
            Text(LibraryViewModel.formatted(video.bytes)).font(.caption).foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Screensaver

    @ViewBuilder private func instructionStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                .frame(width: 15, alignment: .center)
            Text(text).foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 0)
        }
    }

    private var screensaverSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screensaver").font(.title2).fontWeight(.semibold)
            card {
                VStack(alignment: .leading, spacing: 14) {
                    if pluginManager.isActiveScreensaver {
                        Label("Surrealism is your active screensaver", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.medium)).foregroundStyle(.green)
                    } else {
                        Text(pluginManager.isInstalled
                             ? "Ready — make Surrealism your screensaver."
                             : "Set Surrealism as your Mac screensaver.")
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    if !pluginManager.isActiveScreensaver {
                        VStack(alignment: .leading, spacing: 7) {
                            instructionStep(1, "Click “\(pluginManager.isInstalled ? "Set as Screensaver" : "Set Up Screensaver")” — it installs Surrealism and opens Screen Saver settings.")
                            instructionStep(2, "In the list that opens, choose Surrealism.")
                            instructionStep(3, "It runs when your Mac is idle. Reopen Screen Saver Settings anytime to preview or switch.")
                        }
                        .font(.callout)
                        .padding(.top, 2)
                    }

                    if let error = pluginManager.lastError ?? pluginManager.screensaverError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    HStack(spacing: 10) {
                        if !pluginManager.isActiveScreensaver {
                            Button(pluginManager.isInstalled ? "Set as Screensaver" : "Set Up Screensaver") {
                                setUpScreensaver()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(pluginManager.isLoading || pluginManager.isCheckingScreensaver)
                        }
                        Button("Screen Saver Settings") { openScreenSaverSettings() }
                            .buttonStyle(GhostButtonStyle())
                        if pluginManager.isLoading || pluginManager.isCheckingScreensaver {
                            ProgressView().scaleEffect(0.6)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Store

    private var storeSection: some View {
        card {
            HStack(spacing: 14) {
                SurrealismMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get the full surrealism.app library").fontWeight(.semibold)
                    Text("Unlock a growing catalog of surreal loops. Coming soon.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button("Visit surrealism.app") { NSWorkspace.shared.open(storeURL) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: Actions

    private func setUpScreensaver() {
        do {
            if !pluginManager.isInstalled { try pluginManager.install() }
        } catch {
            logger.error("Setup failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // macOS 26 moved screen savers into the Wallpaper/idle system, where
        // flipping the active saver programmatically no longer works reliably.
        // Older macOS can still set it directly; on 26 we open the picker so the
        // user can select Surrealism (the one path that works everywhere).
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            Task { await pluginManager.enableAsScreensaver() }
        }
        openScreenSaverSettings()
    }

    private func openScreenSaverSettings() {
        // macOS 26 (Tahoe) folded the Screen Saver pane into Wallpaper; earlier
        // versions have a dedicated Screen Saver pane. Using the wrong id silently
        // dumps the user on the General pane, so pick by OS version.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let pane = major >= 26 ? "com.apple.Wallpaper-Settings.extension"
                               : "com.apple.ScreenSaver-Settings.extension"
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView()
}
