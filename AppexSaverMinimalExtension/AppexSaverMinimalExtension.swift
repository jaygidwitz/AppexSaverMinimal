//
//  AppexSaverMinimalExtension.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Principal class for the screensaver extension. Specified as
//  NSExtensionPrincipalClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).AppexSaverMinimalExtension`.
//
//  Following Apple's own screensavers (e.g. Arabesque.appex) we keep this
//  minimal — only implement init() and let the framework drive lifecycle.
//

import Foundation
import ScreenSaver

private let logger = AppexLog.logger("Extension")

@objc(AppexSaverMinimalExtension)
class AppexSaverMinimalExtension: ScreenSaverExtension {

    @objc override init() {
        logger.info("AppexSaverMinimalExtension.init() PID=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        super.init()
    }

    deinit {
        logger.info("AppexSaverMinimalExtension.deinit")
    }
}
