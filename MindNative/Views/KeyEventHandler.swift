import SwiftUI
import AppKit

/// NSView wrapper to handle keyboard events like Tab and Space
struct KeyEventHandlingView: NSViewRepresentable {
    var isActive: Bool
    var onKeyDown: (NSEvent) -> Bool
    var onKeyUp: ((NSEvent) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = KeyEventCaptureView()
        view.keyDownHandler = onKeyDown
        view.keyUpHandler = onKeyUp
        view.shouldCaptureKeyboard = isActive
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyEventCaptureView {
            view.keyDownHandler = onKeyDown
            view.keyUpHandler = onKeyUp
            view.shouldCaptureKeyboard = isActive
        }
    }

    class KeyEventCaptureView: NSView {
        var keyDownHandler: ((NSEvent) -> Bool)?
        var keyUpHandler: ((NSEvent) -> Void)?
        var shouldCaptureKeyboard = false {
            didSet {
                requestKeyboardFocusIfNeeded()
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestKeyboardFocusIfNeeded()
        }

        override func keyDown(with event: NSEvent) {
            if let handler = keyDownHandler, handler(event) {
                return // Event was handled
            }
            super.keyDown(with: event)
        }

        override func keyUp(with event: NSEvent) {
            keyUpHandler?(event)
            super.keyUp(with: event)
        }

        private func requestKeyboardFocusIfNeeded() {
            guard shouldCaptureKeyboard else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.shouldCaptureKeyboard,
                      let window = self.window,
                      window.firstResponder !== self else {
                    return
                }
                window.makeFirstResponder(self)
            }
        }
    }
}
