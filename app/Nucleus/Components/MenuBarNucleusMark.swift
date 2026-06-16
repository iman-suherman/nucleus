import SwiftUI

/// SwiftUI preview of the menu bar atom mark (AppKit template image is used in the status item).
struct MenuBarNucleusMark: View {
    var body: some View {
        Image(nsImage: MenuBarNucleusIcon.templateImage())
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(Color.primary)
            .accessibilityLabel("Nucleus")
    }
}
