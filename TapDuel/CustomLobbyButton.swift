//
//  CustomLobbyButton.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/29/25.
//

import SwiftUI

struct CustomLobbyButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.6)) 
                    .frame(width: 80, height: 40)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.6))
                    .frame(width: 68, height: 28)
                    .overlay(
                        Image("LightSketchTexture")
                            .resizable(resizingMode: .tile)
                            .opacity(0.25)
                            .blendMode(.multiply)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                
                Text(title)
                    .font(.custom("DK Lemon Yellow Sun", size: 20))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0.5, y: 0.5)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}



#Preview {
    HStack {
        CustomLobbyButton(title: "Create", color: .green) {}
        CustomLobbyButton(title: "Join", color: .blue) {}
    }
    .padding()
    .background(Color.black)
}


