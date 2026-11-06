import SwiftUI

struct LogoView: View {
    let animator: LogoAnimator

    var body: some View {
        Image(nsImage: animator.currentImage)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 16)
            .accessibilityHidden(true)
    }
}
