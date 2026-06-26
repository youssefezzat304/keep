//
//  CardStyle.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct CardStyle: ViewModifier {
    let backgroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(minWidth: 100, maxWidth: 500, minHeight: 100, maxHeight: 350)
            .background(backgroundColor)
            .cornerRadius(20)
    }
}

extension View {
    func cardStyle(backgroundColor: Color = Color.gray.opacity(0.15)) -> some View {
        self.modifier(CardStyle(backgroundColor: backgroundColor))
    }
}
