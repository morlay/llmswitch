import AppKit
import SwiftUI

struct LLMSwitchOutlineSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let rootView = nsView.superview else {
                return
            }
            suppressOutlines(in: rootView)
        }
    }

    private func suppressOutlines(in view: NSView) {
        if let control = view as? NSControl {
            control.focusRingType = .none
        }

        for subview in view.subviews {
            suppressOutlines(in: subview)
        }
    }
}
