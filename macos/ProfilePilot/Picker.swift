import AppKit

// MARK: - Picker panel

enum PickResult {
    case open(Int)
    case copy
    case cancel
}

final class Picker: NSObject {
    private var result: PickResult = .cancel

    func run(url: URL, targets: [Target]) -> PickResult {
        let width: CGFloat = 344

        let title = NSTextField(labelWithString: "Open link with")
        title.font = .boldSystemFont(ofSize: 13)

        let urlLabel = NSTextField(labelWithString: url.absoluteString)
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 16, bottom: 14, right: 16)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(urlLabel)
        stack.setCustomSpacing(12, after: urlLabel)
        urlLabel.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true

        for (index, target) in targets.enumerated() {
            let button = NSButton(title: target.title, target: self, action: #selector(choose(_:)))
            button.tag = index
            button.controlSize = .large
            let icon = NSWorkspace.shared.icon(forFile: target.appPath)
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.imagePosition = .imageLeading
            // Return opens the first (last-used) entry; 2–9 jump to the rest.
            button.keyEquivalent = index == 0 ? "\r" : (index < 9 ? "\(index + 1)" : "")
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            stack.addArrangedSubview(button)
        }
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        let copyButton = NSButton(title: "Copy Link", target: self, action: #selector(copyLink(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let bottom = NSStackView(views: [copyButton, cancelButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        stack.addArrangedSubview(bottom)

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
        panel.center()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    @objc private func choose(_ sender: NSButton) {
        result = .open(sender.tag)
        NSApp.stopModal()
    }

    @objc private func copyLink(_ sender: NSButton) {
        result = .copy
        NSApp.stopModal()
    }

    @objc private func cancel(_ sender: NSButton) {
        result = .cancel
        NSApp.stopModal()
    }
}
