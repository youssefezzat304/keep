//
//  TimerWorkspaceCard.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct TimerWorkspaceCard: View {
    var body: some View {
        VStack {
            PomodoroTimerPanel()
            FlowTimerPanel()
        }
        .padding()
    }
}

#Preview {
    TimerWorkspaceCard()
}
