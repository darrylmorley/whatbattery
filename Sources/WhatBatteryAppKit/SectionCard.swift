import SwiftUI

/// A titled section on its own surface: the unit every tab is built from.
///
/// Before this the window was one long scroll of headings and hairline rules,
/// which reads as a form rather than an app. A card per section gives each one
/// an edge, so the eye can find where a thing starts and stops, and matches how
/// System Settings groups content, which is the vocabulary Mac users already
/// know.
public struct SectionCard<Content: View, Accessory: View>: View {
    private let title: String?
    private let systemImage: String?
    private let accessory: Accessory
    private let content: Content

    public init(
        _ title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Label {
                            Text(title)
                        } icon: {
                            if let systemImage { Image(systemName: systemImage) }
                        }
                        .scaledFont(.headline)
                    }
                    Spacer(minLength: 12)
                    accessory
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }
}

public extension SectionCard where Accessory == EmptyView {
    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, content: content, accessory: { EmptyView() })
    }
}
