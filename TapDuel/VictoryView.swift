//
//  VictoryView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/9/25.
//

import SwiftUI
import SpriteKit

struct VictoryView: View {
    let result: String
    let onDismissToLobby: () -> Void
    
    @State private var countdown = 5
    
    var body: some View {
        ZStack {
            SpriteView(scene: VictoryViewBackground(size: UIScreen.main.bounds.size))
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text(victoryMessage)
                    .font(.custom("DK Lemon Yellow Sun", size: 60))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(Color("pencilYellow"))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)
                    .padding()
                
                if result == "player" || result == "disconnect" {
                    Text("WINNER!")
                        .font(.custom("DK Lemon Yellow Sun", size: 80))
                        .foregroundColor(Color("pencilGreen"))
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 1, y: 1)
                }
            }
        }
        .onAppear {
            print("🎉 VictoryView appeared. Starting 5-second timer.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                print("⏱ VictoryView timeout reached. Returning to lobby.")
                onDismissToLobby()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private var victoryMessage: String {
        switch result {
        case "player":
            return "Congratulations. \nYou are the"
        case "opponent":
            return "You lost. 😢 \nbut you'll win next time!"
        case "tie":
            return "You tied! \nReturning to Lobby."
        case "disconnect":
            return "Opponent disconnected.\nYou are the"
        default:
            return "Match over."
        }
    }
}
