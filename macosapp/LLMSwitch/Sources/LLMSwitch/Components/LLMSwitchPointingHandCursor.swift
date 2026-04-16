import AppKit
import SwiftUI

private struct LLMSwitchPointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func llmSwitchPointingHandCursor() -> some View {
        modifier(LLMSwitchPointingHandCursorModifier())
    }
}
