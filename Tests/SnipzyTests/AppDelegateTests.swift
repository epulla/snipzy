import AppKit
import Testing
@testable import Snipzy

@MainActor @Suite
struct AppDelegateTests {
    @Test
    func editMenuActionsUseResponderChain() {
        let editMenu = AppDelegate.makeMainMenu().items[1].submenu!
        let actions: [Selector] = [#selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:)), Selector(("undo:")), Selector(("redo:"))]

        for action in actions {
            let item = editMenu.items.first { $0.action == action }
            #expect(item != nil)
            #expect(item?.target == nil)
        }
    }
}
