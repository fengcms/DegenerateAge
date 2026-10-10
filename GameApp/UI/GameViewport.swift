import SwiftUI
import SpriteKit
import AppKit

struct GameViewport: NSViewRepresentable {
    let scene: PrototypeScene
    func makeNSView(context: Context) -> KeyboardGameView {
        let view = KeyboardGameView()
        view.presentScene(scene)
        return view
    }
    func updateNSView(_ view: KeyboardGameView, context: Context) {}
}

final class KeyboardGameView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        guard let scene = scene as? PrototypeScene else { return }
        scene.keyChanged(event.keyCode, down: true, repeating: event.isARepeat)
    }
    override func keyUp(with event: NSEvent) {
        (scene as? PrototypeScene)?.keyChanged(event.keyCode, down: false, repeating: false)
    }
    override func resignFirstResponder() -> Bool {
        (scene as? PrototypeScene)?.clearInput()
        return super.resignFirstResponder()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
