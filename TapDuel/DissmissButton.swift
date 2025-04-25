//
//  DissmissButton.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/21/25.
//

import Foundation
import SwiftUI

struct DismissButton: View {
    let action: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Text("X")
                    .font(.custom("DK Lemon Yellow Sun", size: 24))
                    .foregroundColor(.red)
            }
        }
    }
}
