//
//  SettingsPopupView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import SwiftUI
import GameKit

class GameCenterDelegate: NSObject, GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

struct SettingsPopupView: View {
    @Binding var isPresented: Bool
    @Binding var volume: Double
    @Binding var isMuted: Bool
    @State private var showCopiedAlert = false
    @State private var gameCenterDelegate = GameCenterDelegate()

    var playerID: String
    var version = "1.0.0"

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 24) {
                DismissButton {
                    isPresented = false
                }

                Text("Settings")
                    .font(.custom("DK Lemon Yellow Sun", size: 34))
                    .foregroundColor(Color("pencilYellow"))

                HStack(spacing: 20) {
                    Button(action: {
                        isMuted.toggle()
                        MusicManager.shared.setMuted(isMuted)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(Color.gray)
                    }

                    VStack(alignment: .leading) {
                        Text("Volume")
                            .font(.custom("DK Lemon Yellow Sun", size: 18))
                            .foregroundColor(Color("pencilYellow"))

                        Slider(value: $volume, in: 0...1)
                            .accentColor(Color("pencilYellow"))
                            .onChange(of: volume) { _, newValue in
                                MusicManager.shared.setVolume(Float(newValue))
                            }
                    }
                }

                Button(action: {
                    authenticateAndShowDashboard()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.white)
                        Text("Connect to Game Center")
                            .foregroundColor(.white)
                            .font(.custom("DK Lemon Yellow Sun", size: 20))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color("pencilYellow"))
                    .cornerRadius(20)
                    .shadow(radius: 4)
                }

                VStack(spacing: 4) {
                    Text("Version \(version)")
                        .font(.custom("DK Lemon Yellow Sun", size: 14))
                        .foregroundColor(Color("pencilYellow").opacity(0.7))

                    Button(action: {
                        UIPasteboard.general.string = playerID
                        showCopiedAlert = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedAlert = false
                        }
                    }) {
                        Text("Player ID: \(playerID)")
                            .font(.custom("DK Lemon Yellow Sun", size: 14))
                            .foregroundColor(Color("pencilYellow"))
                            .underline()
                    }

                    if showCopiedAlert {
                        Text("Copied!")
                            .font(.custom("DK Lemon Yellow Sun", size: 12))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()
            .background(
                ZStack {
                    Color(white: 0.95)
                    Image("45DegreeFabricLight")
                        .resizable(resizingMode: .tile)
                        .opacity(0.15)
                }
            )
            .cornerRadius(24)
            .padding(.horizontal, 40)
        }
    }
    
    private func authenticateAndShowDashboard() {
        let localPlayer = GKLocalPlayer.local

        if localPlayer.isAuthenticated {
            print("✅ Already authenticated. Showing dashboard.")
            showGameCenterDashboard()
            return
        }

        localPlayer.authenticateHandler = { viewController, error in
            if let viewController = viewController {
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first?.rootViewController {
                    rootVC.present(viewController, animated: true)
                }
            } else if localPlayer.isAuthenticated {
                print("✅ Game Center authenticated: \(localPlayer.displayName)")
                showGameCenterDashboard()
            } else {
                print("❌ Game Center authentication failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    private func showGameCenterDashboard() {
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = gameCenterDelegate

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(vc, animated: true)
        }
    }
}
