import SwiftUI

extension View {
    func editableSurface() -> some View {
        self
            .padding(3)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}
