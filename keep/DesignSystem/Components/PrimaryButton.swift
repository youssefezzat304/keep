//
//  TabCard.swift
//  keep
//
//  Created by Youssef Abdelrahim on 26.06.26.
//

import SwiftUI

struct PrimaryButton: View {
    let buttonTitle: String
    
    var body: some View {
        Button(buttonTitle) {
            print("clicked")
        }
        .buttonStyle(.plain)
        .frame(width: 90, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
        )
    }
}

#Preview {
    PrimaryButton(buttonTitle: "Settings")
}
