//
//  PluginManager.swift
//  AppexSaver
//
//  Manages the installation and status of the screensaver extension.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.glouel.screensaver.AppexSaver", category: "PluginManager")

@MainActor
class PluginManager: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var installedVersion: String?
    @Published var installedPath: String?
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let bundleIdentifier = "com.glouel.screensaver.AppexSaver.AppexSaverExtension"

    /// Path to the embedded extension in the app bundle
    var embeddedExtensionPath: String? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("AppexSaverExtension.appex").path
    }

    /// Version of the embedded extension
    var embeddedVersion: String? {
        guard let path = embeddedExtensionPath,
              let bundle = Bundle(path: path),
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return version
    }

    init() {
        checkInstallationStatus()
    }

    /// Check if the extension is registered with pluginkit
    func checkInstallationStatus() {
        isLoading = true
        lastError = nil

        Task {
            do {
                let (isRegistered, path, version) = try await queryPluginKit()
                await MainActor.run {
                    self.isInstalled = isRegistered
                    self.installedPath = path
                    self.installedVersion = version
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isInstalled = false
                    self.installedPath = nil
                    self.installedVersion = nil
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Query pluginkit for our extension's registration status
    private func queryPluginKit() async throws -> (Bool, String?, String?) {
        let output = try runProcess("/usr/bin/pluginkit", arguments: ["-m", "-v", "-p", "com.apple.screensaver"])

        // Parse output for our bundle identifier
        // Format: "    com.glouel.AppexSaver.AppexSaverExtension(1.0) <path>"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(bundleIdentifier) {
                logger.info("Found extension in pluginkit output: \(line, privacy: .public)")

                // Extract version (in parentheses)
                var version: String?
                if let versionStart = line.firstIndex(of: "("),
                   let versionEnd = line.firstIndex(of: ")") {
                    let start = line.index(after: versionStart)
                    version = String(line[start..<versionEnd])
                }

                // Extract path (starts with "/" after UUID and timestamp)
                var path: String?
                if let pathStart = line.range(of: "/", options: [], range: line.startIndex..<line.endIndex) {
                    path = String(line[pathStart.lowerBound...])
                }

                return (true, path, version)
            }
        }

        return (false, nil, nil)
    }

    /// Install the extension using pluginkit
    func install() throws {
        guard let extensionPath = embeddedExtensionPath else {
            throw PluginError.embeddedExtensionNotFound
        }

        guard FileManager.default.fileExists(atPath: extensionPath) else {
            throw PluginError.embeddedExtensionNotFound
        }

        logger.info("Installing extension from: \(extensionPath, privacy: .public)")

        isLoading = true
        lastError = nil

        do {
            _ = try runProcess("/usr/bin/pluginkit", arguments: ["-a", extensionPath])
            logger.info("Extension installed successfully")

            // Re-check status after installation
            checkInstallationStatus()
        } catch {
            isLoading = false
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Uninstall the extension using pluginkit
    func uninstall() throws {
        // Use the installed path if available, otherwise use the embedded path
        let extensionPath: String
        if let installed = installedPath, !installed.isEmpty {
            extensionPath = installed
        } else if let embedded = embeddedExtensionPath {
            extensionPath = embedded
        } else {
            throw PluginError.extensionPathNotFound
        }

        logger.info("Uninstalling extension at: \(extensionPath, privacy: .public)")

        isLoading = true
        lastError = nil

        do {
            _ = try runProcess("/usr/bin/pluginkit", arguments: ["-r", extensionPath])
            logger.info("Extension uninstalled successfully")

            // Re-check status after uninstallation
            checkInstallationStatus()
        } catch {
            isLoading = false
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Run a process and return its output
    private func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        logger.debug("Process output: \(output, privacy: .public)")

        if process.terminationStatus != 0 {
            logger.warning("Process exited with status: \(process.terminationStatus)")
            // Don't throw for non-zero exit - pluginkit returns non-zero when no matches found
        }

        return output
    }
}

enum PluginError: LocalizedError {
    case embeddedExtensionNotFound
    case extensionPathNotFound
    case installationFailed(String)
    case uninstallationFailed(String)

    var errorDescription: String? {
        switch self {
        case .embeddedExtensionNotFound:
            return "Embedded extension not found in app bundle"
        case .extensionPathNotFound:
            return "Extension path not found"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        }
    }
}
