import SwiftUI
import AppKit

extension View {
    /// macOS'ta fare imlecini pointer (el) yapar
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}
