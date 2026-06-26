//
//  ActiveTargetHeader.swift
//  keep
//
//  Created by Youssef Abdelrahim on 22.06.26.
//

import SwiftUI

struct ActiveTargetHeader: View {
    var body: some View {
        HStack {
            Text("Untitled")
            Spacer()
            
            Button("Change") {
                print("Change project/task")
            }
        }
        .padding()
        .frame(minWidth:100, maxWidth:1000, minHeight:50, maxHeight:50)
    }
}

#Preview {
    ActiveTargetHeader()
}
