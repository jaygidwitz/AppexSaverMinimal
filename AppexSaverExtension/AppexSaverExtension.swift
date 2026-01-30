//
//  AppexSaverExtension.swift
//  AppexSaverExtension
//
//  Principal class for the screensaver extension.
//  This class is specified as NSExtensionPrincipalClass in Info.plist.
//
//  Simplified to match Apple's Arabesque.appex pattern:
//  - Only implements init()
//  - Does NOT override any lifecycle methods
//  - Lets the framework handle everything
//

import Foundation
import ScreenSaver
import os.log

private let logger = Logger(subsystem: "com.glouel.screensaver.AppexSaver", category: "Extension")

/// Principal class for the screensaver app extension.
/// Minimal implementation matching Apple's pattern.
@objc(AppexSaverExtension)
class AppexSaverExtension: ScreenSaverExtension {

    @objc override init() {
        logger.info("AppexSaverExtension.init()")
        logger.info("  PID: \(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        super.init()
    }

    deinit {
        logger.info("AppexSaverExtension.deinit")
    }
}
