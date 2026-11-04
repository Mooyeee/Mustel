import SwiftUI

/// A vertical scroll view that only scrolls when its content is taller than `maxHeight`.
///
/// When the content fits, it is laid out at its natural height without a scroll view,
/// so small lists never clip or scroll.
struct ScrollViewIfNeeded<Content: View>: View {
    let maxHeight: CGFloat
    private let content: Content

    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        Group {
            if contentHeight > maxHeight {
                ScrollView(.vertical) {
                    content
                        .background(ContentHeightReader())
                }
                .frame(height: maxHeight)
            } else {
                content
                    .background(ContentHeightReader())
            }
        }
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            contentHeight = height
        }
    }
}

private struct ContentHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ContentHeightPreferenceKey.self,
                value: proxy.size.height
            )
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
