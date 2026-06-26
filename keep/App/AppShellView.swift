//
//  AppShellView.swift
//  keep
//
//  Created by Youssef Abdelrahim on 26.06.26.
//


import SwiftUI

struct AppShellView: View {
    var body: some View {
        VStack(spacing: 0) {
            NavBar()
                .padding(.top, 20)
                .padding(.horizontal, 32)
            
            FocusSessionView()
                .frame(maxWidth: 1100)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    AppShellView()
}
