//
//  AppexSaverViewController.swift
//  AppexSaverExtension
//
//  Main view controller for the screensaver animation.
//  Specified as ScreenSaverViewControllerClass in Info.plist.
//
//  Simplified to match Apple's Arabesque.appex pattern:
//  - Only implements init(nibName:bundle:), init(coder:), loadView()
//  - Does NOT override ViewBridge lifecycle methods
//  - Lets the framework handle everything
//

import AppKit
import ScreenSaver
import os.log

private let logger = Logger(subsystem: "com.glouel.screensaver.AppexSaver", category: "ViewController")

/// View controller that manages the screensaver view.
/// Minimal implementation matching Apple's pattern.
@objc(AppexSaverViewController)
class AppexSaverViewController: ScreenSaverViewController {

    /// Strong reference to prevent view from being deallocated
    private var saverView: AppexSaverView?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        logger.info("AppexSaverViewController.init(nibName:bundle:)")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        logger.info("AppexSaverViewController.init(coder:)")
        super.init(coder: coder)
    }

    deinit {
        logger.info("AppexSaverViewController.deinit - frameCount: \(self.saverView?.frameCount ?? -1)")
    }

    /// Called by the framework to create the view.
    /// Apple's screensavers override this standard NSViewController method.
    override func loadView() {
        logger.info("loadView() called")

        // Get the frame from the main screen, or use a default
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        logger.info("  frame: \(frame.size.width, privacy: .public) x \(frame.size.height, privacy: .public)")

        // Determine if this is a preview by checking the frame size
        let isPreview = frame.width < 400
        logger.info("  isPreview: \(isPreview)")

        saverView = AppexSaverView(frame: frame, isPreview: isPreview)

        if let sv = saverView {
            // Only set self.view - do NOT set representedView
            // Apple's screensavers don't touch representedView
            self.view = sv
            logger.info("loadView() completed - view set")
        } else {
            logger.error("Failed to create AppexSaverView, using fallback")
            self.view = NSView(frame: frame)
        }
    }
}
