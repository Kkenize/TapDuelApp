//
//  HomeView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import SwiftUI
import SpriteKit

struct HomeView: View {
    @State private var showLobby = false
    @State private var fadeOutText = false
    @State private var bounce = false

    var body: some View {
        ZStack {
            SpriteView(scene: HomeViewBackground(size: UIScreen.main.bounds.size))
                .ignoresSafeArea()

            if showLobby {
                LobbyView()
                    .transition(.opacity)
            }

            if !showLobby {
                VStack(spacing: 16) {
                    Text("Tap Duel")
                        .font(.custom("DK Lemon Yellow Sun", size: 100))
                        .foregroundColor(Color("pencilYellow"))
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)

                    Text("Tap anywhere to start")
                        .font(.custom("DK Lemon Yellow Sun", size: 30))
                        .foregroundColor(Color("pencilYellow"))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                        .scaleEffect(bounce ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: bounce)
                        .onAppear { bounce = true }
                }
                .opacity(fadeOutText ? 0 : 1)
                .scaleEffect(fadeOutText ? 0.9 : 1)
                .animation(.easeInOut(duration: 0.5), value: fadeOutText)
                .onTapGesture {
                    fadeOutText = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showLobby = true
                    }
                }
                .contentShape(Rectangle())
            }
        }
    }
}

#Preview {
    HomeView()
}


