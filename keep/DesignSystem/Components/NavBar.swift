//
//  NavBar.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct NavBar: View {
    var body: some View {
       HStack {
           PrimaryButton(buttonTitle: "Home")
           PrimaryButton(buttonTitle: "Stats")
           PrimaryButton(buttonTitle: "Settings")
        }
    }
}

#Preview {
    NavBar()
}
