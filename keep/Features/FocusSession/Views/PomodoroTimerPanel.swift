//
//  PomodoroTimerPanel.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct PomodoroTimerPanel: View {
    var body: some View {
        HStack {
            Text("Pomodoro ")
                .font(.system(size: 20))
            Text("25:00")
                .font(.system(size: 100))
            Button("Start") {
                print("Start pomodoro")
            }
        }
        .padding()

    }
}

#Preview {
    PomodoroTimerPanel()
}
