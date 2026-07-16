import AppKit
import Testing
@testable import AgentUsageMonitor

@MainActor
@Test func applicationMenuRoutesStandardTextEditingCommandsThroughResponderChain() throws {
    let mainMenu = ApplicationMenu.makeMainMenu(applicationName: "Agent Usage Monitor")
    let editMenu = try #require(mainMenu.items.first { $0.submenu?.title == "Edit" }?.submenu)

    let expectedCommands: [(title: String, action: Selector, key: String)] = [
        ("Undo", Selector(("undo:")), "z"),
        ("Cut", #selector(NSText.cut(_:)), "x"),
        ("Copy", #selector(NSText.copy(_:)), "c"),
        ("Paste", #selector(NSText.paste(_:)), "v"),
        ("Select All", #selector(NSText.selectAll(_:)), "a")
    ]

    for command in expectedCommands {
        let item = try #require(editMenu.items.first { $0.action == command.action })
        #expect(item.title == command.title)
        #expect(item.keyEquivalent == command.key)
        #expect(item.keyEquivalentModifierMask == [.command])
        #expect(item.target == nil)
    }

    let redo = try #require(editMenu.items.first { $0.action == Selector(("redo:")) })
    #expect(redo.keyEquivalent == "z")
    #expect(redo.keyEquivalentModifierMask == [.command, .shift])
}
