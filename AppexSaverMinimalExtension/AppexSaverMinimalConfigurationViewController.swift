//
//  AppexSaverMinimalConfigurationViewController.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  The sheet shown when the user clicks "Options…" next to Surrealism in the
//  Screen Saver settings. The screensaver itself has nothing to tune — the
//  library, license, and setup all live in the Surrealism app — so this points
//  the user there via the `surrealism://` URL scheme (registered by the host).
//

import AppKit

private let logger = AppexLog.logger("Configuration")

@objc(AppexSaverMinimalConfigurationViewController)
class AppexSaverMinimalConfigurationViewController: NSViewController {

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 190))

        let title = NSTextField(labelWithString: "Surrealism")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center

        let body = NSTextField(wrappingLabelWithString:
            "Your loops, library, and license live in the Surrealism app. Open it to add loops, manage your library, or unlock the full collection.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.alignment = .center

        let open = NSButton(title: "Open Surrealism", target: self, action: #selector(openApp(_:)))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"

        let done = NSButton(title: "Done", target: self, action: #selector(dismissSheet(_:)))
        done.bezelStyle = .rounded

        [title, body, open, done].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26),

            open.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            open.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            open.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),

            done.topAnchor.constraint(equalTo: open.bottomAnchor, constant: 8),
            done.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: 400, height: 190)
    }

    @objc private func openApp(_ sender: Any?) {
        if let url = URL(string: "surrealism://open") {
            logger.info("Opening host app via surrealism:// scheme")
            NSWorkspace.shared.open(url)
        }
        dismissSheet(sender)
    }

    @objc private func dismissSheet(_ sender: Any?) {
        if let window = self.view.window, let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            self.dismiss(nil)
        }
    }
}
