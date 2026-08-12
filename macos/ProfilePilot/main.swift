import AppKit

// ProfilePilot: registers as the default browser and routes every URL handed
// to it into the browser/profile you pick. Browsers come from
// ~/.config/profilepilot/config.json; with no config it falls back to Chrome
// and its profiles. Launched with no URL it opens the Settings window.

// A minimal main menu so Cmd+Q/W and text editing shortcuts work in the
// Settings window (LSUIElement apps get no menu for free).
func makeMainMenu() -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "Quit ProfilePilot",
                               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editItem.submenu = editMenu
    main.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(NSMenuItem(title: "Close Window",
                                  action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    windowItem.submenu = windowMenu
    main.addItem(windowItem)

    return main
}

let app = NSApplication.shared
app.mainMenu = makeMainMenu()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
