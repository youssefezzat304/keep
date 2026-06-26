//
//  FocusSessionView.swift
//  keep
//
//  Created by Youssef Abdelrahim on 20.06.26.
//

import SwiftUI

struct FocusSessionView: View {
    var body: some View {
        VStack {
            ActiveTargetHeader()
            
            Spacer()
            
            TimerWorkspaceCard()
            
            Spacer()
            
            HStack {
                MusicPlayerCard()
                
                Spacer()
                
                TasksCard()
            }
            .frame(maxWidth:1000)
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    FocusSessionView()
}
