import SwiftUI

struct StatusDot: View {
    let enabled: Bool
    var body: some View {
        Circle()
            .fill(enabled ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
    }
}
