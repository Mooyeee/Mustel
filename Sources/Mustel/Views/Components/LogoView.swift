import SwiftUI

struct LogoView: View {
    let animator: LogoAnimator

    var body: some View {
        Image(nsImage: animator.currentImage)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 35, height: 20)
            .accessibilityHidden(true)
    }
}
