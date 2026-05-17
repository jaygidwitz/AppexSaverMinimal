//
//  AppexSaverMinimalConfigurationViewController.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Configuration sheet displayed when the user clicks "Options" next to the
//  screensaver in System Settings. Specified as
//  ScreenSaverConfigurationSheetViewControllerClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).AppexSaverMinimalConfigurationViewController`.
//
//  This sample has no real configuration; it shows the bare minimum needed
//  for the sheet to dismiss cleanly. SwiftUI works here too — wrap your
//  SwiftUI view in NSHostingController and use it as self.view.
//

import AppKit

private let logger = AppexLog.logger("Configuration")

@objc(AppexSaverMinimalConfigurationViewController)
class AppexSaverMinimalConfigurationViewController: NSViewController {

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        logger.info("init(nibName:bundle:)")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        logger.info("init(coder:)")
        super.init(coder: coder)
    }

    override func loadView() {
        logger.info("loadView()")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))

        let label = NSTextField(labelWithString: "AppexSaverMinimal")
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let button = NSButton(title: "OK", target: self, action: #selector(dismissSheet(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),

            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: 300, height: 120)
    }

    @objc private func dismissSheet(_ sender: Any?) {
        if let window = self.view.window, let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            self.dismiss(nil)
        }
    }
}
