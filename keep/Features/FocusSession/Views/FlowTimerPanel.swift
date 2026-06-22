//
//  FlowTimerPanel.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct FlowTimerPanel: View {
    var body: some View {
        HStack {
            Text("Flow ")
                .font(.system(size: 20))
            Text("00:00:00")
                .font(.system(size: 70))
                
            Button("Start") {
                print("Start Flow")
            }
        }
        .padding()
    }
}

#Preview {
    FlowTimerPanel()
}
