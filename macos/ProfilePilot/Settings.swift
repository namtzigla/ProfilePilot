import AppKit
import UniformTypeIdentifiers

// MARK: - Settings window

final class SettingsController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                NSWindowDelegate, NSTextFieldDelegate {
    private var entries: [BrowserEntry]
    private let window: NSWindow
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let defaultButton = NSButton(title: "Set as Default Browser", target: nil, action: nil)
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    private let upButton = NSButton(title: "", target: nil, action: nil)
    private let downButton = NSButton(title: "", target: nil, action: nil)

    override init() {
        // First run (no config yet) seeds the list with every installed browser.
        if FileManager.default.fileExists(atPath: configFileURL().path) {
            entries = loadConfig().config.browsers
        } else {
            entries = starterEntries()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "ProfilePilot Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = buildContent()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refreshDefaultStatus()
        refreshSelectionButtons()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // MARK: Layout

    private func buildContent() -> NSView {
        let contentWidth: CGFloat = 540

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let title = NSTextField(labelWithString: "ProfilePilot")
        title.font = .boldSystemFont(ofSize: 15)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, statusLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        defaultButton.target = self
        defaultButton.action = #selector(setDefault(_:))
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 10
        header.addView(iconView, in: .leading)
        header.addView(titleStack, in: .leading)
        header.addView(defaultButton, in: .trailing)
        header.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let browsersLabel = NSTextField(labelWithString: "Browsers shown in the picker")
        browsersLabel.font = .boldSystemFont(ofSize: 12)

        for (identifier, columnTitle, width) in [("enabled", "On", 30.0),
                                                 ("browser", "Browser", 185.0),
                                                 ("name", "Display Name", 145.0),
                                                 ("default", "Default", 55.0),
                                                 ("profiles", "Profiles", 55.0)] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = columnTitle
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let addButton = NSButton(title: "", target: self, action: #selector(addClicked(_:)))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add browser")
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove browser")
        upButton.target = self
        upButton.action = #selector(moveUp(_:))
        upButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Move up")
        downButton.target = self
        downButton.action = #selector(moveDown(_:))
        downButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Move down")

        let listButtons = NSStackView()
        listButtons.orientation = .horizontal
        listButtons.spacing = 6
        listButtons.addView(addButton, in: .leading)
        listButtons.addView(removeButton, in: .leading)
        listButtons.addView(upButton, in: .leading)
        listButtons.addView(downButton, in: .leading)
        listButtons.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let hint = NSTextField(labelWithString:
            "On shows or hides a browser without deleting it. Default sorts that browser first so Return opens it; with no default, the picker remembers your last pick. Chromium, Firefox, and Safari expand into one entry per profile — Safari needs Accessibility permission (asked on first use) and access to Safari data. Extra args and custom profile paths live in the JSON.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = contentWidth
        hint.widthAnchor.constraint(lessThanOrEqualToConstant: contentWidth).isActive = true

        let editJSONButton = NSButton(title: "Edit JSON…", target: self, action: #selector(editJSON(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveButton.keyEquivalent = "\r"
        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.addView(editJSONButton, in: .leading)
        bottom.addView(cancelButton, in: .trailing)
        bottom.addView(saveButton, in: .trailing)
        bottom.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(makeSeparator(width: contentWidth))
        stack.addArrangedSubview(browsersLabel)
        stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(listButtons)
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(14, after: hint)
        stack.addArrangedSubview(bottom)
        return stack
    }

    private func makeSeparator(width: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }

    private func refreshDefaultStatus() {
        let isDefault = isDefaultBrowser()
        statusLabel.stringValue = isDefault
            ? "ProfilePilot is your default browser."
            : "Not the default browser — links won't reach the picker yet."
        defaultButton.isHidden = isDefault
    }

    private func refreshSelectionButtons() {
        let row = tableView.selectedRow
        removeButton.isEnabled = row >= 0
        upButton.isEnabled = row > 0
        downButton.isEnabled = row >= 0 && row < entries.count - 1
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "enabled":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            checkbox.state = entry.enabled != false ? .on : .off
            checkbox.toolTip = "Show this browser in the picker"
            return checkbox
        case "browser":
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: appBaseName(entry.app))
            let imageView = NSImageView()
            if resolveAppPath(entry.app) == nil {
                label.textColor = .disabledControlTextColor
                label.toolTip = "Not installed — skipped in the picker"
            } else if let path = resolveAppPath(entry.app) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 18, height: 18)
                imageView.image = icon
                if entry.enabled == false {
                    label.textColor = .disabledControlTextColor
                }
            }
            let cellStack = NSStackView(views: [imageView, label])
            cellStack.orientation = .horizontal
            cellStack.spacing = 6
            cellStack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(cellStack)
            NSLayoutConstraint.activate([
                cellStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                cellStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cellStack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
            return cell
        case "name":
            let field = NSTextField(string: entry.name ?? "")
            field.placeholderString = shortBrowserNames[appBaseName(entry.app)] ?? appBaseName(entry.app)
            field.isBordered = false
            field.drawsBackground = false
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
            return field
        case "default":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleDefault(_:)))
            checkbox.state = entry.isDefault == true ? .on : .off
            checkbox.toolTip = "Default browser: sorts first in the picker so Return opens it. Uncheck to fall back to remembering your last pick."
            return checkbox
        case "profiles":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleProfiles(_:)))
            let capable = isProfileCapable(entry)
            checkbox.state = (entry.profiles ?? capable) ? .on : .off
            checkbox.isEnabled = capable
            checkbox.toolTip = capable ? "Show one entry per browser profile"
                                       : "Profile listing is only supported for Chromium and Firefox browsers"
            return checkbox
        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshSelectionButtons()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard row >= 0, row < entries.count else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        entries[row].name = value.isEmpty ? nil : value
    }

    @objc private func toggleProfiles(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        entries[row].profiles = sender.state == .on
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        entries[row].enabled = sender.state == .on ? nil : false
        reload(selecting: tableView.selectedRow)
    }

    // Behaves like a radio group, except unchecking the current default is
    // allowed (no default → the picker remembers the last choice instead).
    @objc private func toggleDefault(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        let makeDefault = sender.state == .on
        for index in entries.indices {
            entries[index].isDefault = nil
        }
        if makeDefault {
            entries[row].isDefault = true
        }
        reload(selecting: tableView.selectedRow)
    }

    // MARK: List actions

    private func reload(selecting row: Int?) {
        window.makeFirstResponder(nil)
        tableView.reloadData()
        if let row, row >= 0, row < entries.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshSelectionButtons()
    }

    @objc private func addClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let configured = Set(entries.compactMap { resolveAppPath($0.app) })
        for url in installedBrowsers() where !configured.contains(url.path) {
            let item = NSMenuItem(title: appBaseName(url.path), action: #selector(addBrowser(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: "Other…", action: #selector(addOther(_:)), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addBrowser(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        appendEntry(forPath: path)
    }

    @objc private func addOther(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appendEntry(forPath: url.path)
    }

    private func appendEntry(forPath path: String) {
        let app = canonicalApp(forPath: path)
        entries.append(BrowserEntry(name: shortBrowserNames[appBaseName(app)], app: app))
        reload(selecting: entries.count - 1)
    }

    @objc private func removeSelected(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        window.makeFirstResponder(nil)
        entries.remove(at: row)
        reload(selecting: min(row, entries.count - 1))
    }

    @objc private func moveUp(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row > 0 else { return }
        window.makeFirstResponder(nil)
        entries.swapAt(row, row - 1)
        reload(selecting: row - 1)
    }

    @objc private func moveDown(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count - 1 else { return }
        window.makeFirstResponder(nil)
        entries.swapAt(row, row + 1)
        reload(selecting: row + 1)
    }

    // MARK: Footer actions

    @objc private func setDefault(_ sender: NSButton) {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "http"
        ) { _ in
            DispatchQueue.main.async { self.refreshDefaultStatus() }
        }
    }

    @objc private func editJSON(_ sender: NSButton) {
        let url = configFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            writeConfig(entries)
        }
        NSWorkspace.shared.open(url)
        window.close()
    }

    @objc private func save(_ sender: NSButton) {
        window.makeFirstResponder(nil)  // commit any in-progress name edit
        if !writeConfig(entries) {
            let alert = NSAlert()
            alert.messageText = "Could not save config"
            alert.informativeText = configFileURL().path
            alert.runModal()
            return
        }
        window.close()
    }

    @objc private func cancel(_ sender: NSButton) {
        window.close()
    }
}
