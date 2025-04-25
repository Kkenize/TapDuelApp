//
//  GameReadyView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/2/25.
//

import SwiftUI
import SpriteKit
import GameKit

struct GameReadyView: View {
    @ObservedObject var firestore: FirestoreManager
    @ObservedObject var gameManager: GameManager
    var onCountdownComplete: () -> Void
    
    @Binding var shouldGoToReadyView: Bool

    @State private var countdown = 5
    @State private var timerStarted = false
    @State private var hasRequestedStart = false
    @State private var shouldNavigateToGame = false
    
    @State private var showVictory = false
    @State private var shouldDismissGameView = false
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SpriteView(scene: GameReadyViewBackground(size: UIScreen.main.bounds.size))
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    Text("Tap with 1 finger, 2 fingers or 3 fingers!")
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .foregroundColor(Color("pencilBlue"))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)

                    Text("1 finger > 2 fingers, 2 fingers > 3 fingers, 3 fingers > 1 finger")
                        .font(.custom("DK Lemon Yellow Sun", size: 30))
                        .foregroundColor(Color("pencilGreen"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.15), radius: 1, x: 0.5, y: 0.5)
                    
                    Text("There is a 0 to 3 seconds random countdown when the round begins so be ready!")
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .foregroundColor(Color("pencilGreen"))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.15), radius: 1, x: 0.5, y: 0.5)
                    
                    Text("If there is a tie, whoever taps faster wins the round!")
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .foregroundColor(Color("pencilRed"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.15), radius: 1, x: 0.5, y: 0.5)

                    Text("Round \(gameManager.currentRound) of 7 starting in...")
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .foregroundColor(Color("pencilYellow").opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)

                    Text("\(countdown)")
                        .font(.custom("DK Lemon Yellow Sun", size: 80))
                        .foregroundColor(Color("pencilRed"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)

                    Spacer()

                    HStack(alignment: .center, spacing: 8) {
                        HStack {
                            Text("\(firestore.playerDisplayName):")
                                .font(.custom("DK Lemon Yellow Sun", size: 20))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundColor(Color("pencilGreen"))
                        }

                        HStack(spacing: 12) {
                            ForEach(0..<7) { index in
                                let result = index < gameManager.roundResults.count ? gameManager.roundResults[index] : nil
                                SketchSymbolView(name: symbol(for: result), color: color(for: result))
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .onAppear {
                print("🎬 GameReadyView appeared. Starting countdown.")
                firestore.clearEarlyTapSignal()
                
                countdown = 5
                timerStarted = false
                hasRequestedStart = false
                shouldNavigateToGame = false
                
                DispatchQueue.main.async {
                    shouldGoToReadyView = false
                }
                
                print("♻️ Resetting hasAdvancedRound for new round.")
                gameManager.hasAdvancedRound = false

                MusicManager.shared.playGameMusic()
                
                firestore.fetchRoundNumber { round in
                    if let round = round {
                        DispatchQueue.main.async {
                            if gameManager.lastSyncedRound != round {
                                print("🔄 Updating lastSyncedRound: \(gameManager.lastSyncedRound) → \(round)")
                                gameManager.lastSyncedRound = round
                                gameManager.hasIncrementedRound = false
                            } else {
                                print("⚠️ Skipping lastSyncedRound update — same round as before.")
                            }
                            gameManager.currentRound = round
                            print("📥 Synced round number from Firestore: \(round)")
                        }
                    }
                }
                
                print("🧹 Clearing START_MATCH signal on appear.")
                firestore.clearStartMatchSignal()
                firestore.clearSignalIfMatches("ADVANCE_ROUND")

                startCountdown()
            }
            .onDisappear {
                print("👋 GameReadyView disappeared. Resetting navigation state.")
                shouldNavigateToGame = false
            }
            .onChange(of: firestore.signal) { _, newSignal in
                print("📡 Received Firestore signal: \(newSignal)")
                
                if newSignal == "START_MATCH" {
                    print("✅ START_MATCH received. Navigating to GameView.")
                    shouldNavigateToGame = true
                } else if newSignal == "OPPONENT_DISCONNECTED" {
                    print("☠️ Opponent disconnected in GameReadyView. Navigating to VictoryView.")
                    showVictory = true
                }
            }
            .navigationDestination(isPresented: $shouldNavigateToGame) {
                GameView(
                    firestore: firestore,
                    gameManager: gameManager,
                    onRoundComplete: onCountdownComplete
                )
            }
            .onChange(of: shouldNavigateToGame) { _, newValue in
                print("🚀 Navigation trigger toggled. shouldNavigateToGame = \(newValue)")
            }
            .fullScreenCover(isPresented: $showVictory) {
                VictoryView(
                    result: "disconnect",
                    onDismissToLobby: {
                        print("🎯 VictoryView callback triggered. Returning to lobby from GameReadyView.")
                        onCountdownComplete()
                        dismiss()
                    }
                )
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private func startCountdown() {
        guard !timerStarted else {
            print("⏳ Countdown already started, skipping.")
            return
        }

        timerStarted = true
        print("⏱ Countdown started.")

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
                print("⏳ Countdown: \(countdown)")
            } else {
                timer.invalidate()

                guard !hasRequestedStart else {
                    print("⚠️ Already requested START_MATCH, skipping.")
                    return
                }

                hasRequestedStart = true
                print("⏰ Countdown complete. Requesting match start from Firestore.")
                firestore.requestStartMatch()
            }
        }
    }
    
    private func symbol(for result: playerWinState?) -> String {
        switch result {
        case .win: return "check-circle"
        case .lose: return "x-circle"
        case .tie: return "minus-circle"
        case .earlyTap: return "x-circle"
        default: return "circle"
        }
    }

    private func color(for result: playerWinState?) -> Color {
        switch result {
        case .win: return Color("pencilGreen")
        case .lose, .earlyTap: return Color("pencilRed")
        case .tie: return Color("pencilGray")
        default: return Color("pencilGray").opacity(0.3)
        }
    }
}

struct SketchSymbolView: View {
    let name: String
    let color: Color

    var body: some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundColor(color)
            .rotationEffect(.degrees(Double.random(in: -4...4))) 
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0.5, y: 0.5)
    }
}
