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
            
            TimerWorkspaceCard()
            
            HStack {
                MusicPlayerCard()
                
                TasksCard()
            }
        }
        .padding()
    }
}

#Preview {
    FocusSessionView()
}
