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

    @Test
    func newCaptureReplacesOnlyUnannotatedEditors() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let canvas = EditorCanvas(image: image)
        canvas.addText("keep", at: CGPoint(x: 0.5, y: 0.5))
        let plain = EditorWindowController(image: image)
        let annotated = EditorWindowController(image: image, annotations: canvas.annotations)
        let drawMode = EditorWindowController(image: image, drawOn: CGRect(x: 0, y: 0, width: 10, height: 10))

        #expect(AppDelegate.staleEditors([plain, annotated, drawMode]) == [plain])
    }
}
