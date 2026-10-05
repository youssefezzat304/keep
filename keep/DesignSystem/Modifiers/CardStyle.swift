import SwiftUI

struct CardStyle: ViewModifier {
    let backgroundColor: Color

    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
    }
}

extension View {
    func cardStyle(backgroundColor: Color = KeepTheme.surface) -> some View {
        modifier(CardStyle(backgroundColor: backgroundColor))
    }
}
