//
//  AppexSaverConfigurationViewController.swift
//  AppexSaverExtension
//
//  Configuration sheet view controller for the screensaver.
//  Specified as ScreenSaverConfigurationSheetViewControllerClass in Info.plist.
//

import AppKit
import os.log

private let logger = Logger(subsystem: "com.glouel.AppexSaver", category: "Configuration")

/// View controller for the screensaver configuration sheet.
@objc(AppexSaverConfigurationViewController)
class AppexSaverConfigurationViewController: NSViewController {

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        logger.info("AppexSaverConfigurationViewController.init(nibName:bundle:)")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        logger.info("AppexSaverConfigurationViewController.init(coder:)")
        super.init(coder: coder)
    }

    override func loadView() {
        logger.info("loadView()")

        // Create container view
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))

        // Create label
        let label = NSTextField(labelWithString: "Appex Saver")
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(label)

        // Create OK button
        let button = NSButton(title: "OK", target: self, action: #selector(dismissSheet(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(button)

        // Layout constraints
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            label.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),

            button.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        self.view = containerView
        self.preferredContentSize = NSSize(width: 300, height: 120)
    }

    @objc private func dismissSheet(_ sender: Any?) {
        logger.info("dismissSheet()")
        if let window = self.view.window, let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            self.dismiss(nil)
        }
    }
}
