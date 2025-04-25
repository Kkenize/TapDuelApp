//
//  GameView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import SwiftUI
import FirebaseFirestore
import SpriteKit

struct GameView: View {
    @ObservedObject var firestore: FirestoreManager
    @ObservedObject var gameManager: GameManager
    var onRoundComplete: () -> Void
    
    @Environment(\.dismiss) private var dismissToLobby
    
    @State private var opponentForfeited = false
    @State private var didForfeit = false
    @State private var isWinner = false
    @State private var showForfeitOverlay = false
    @State private var fingerCount = 0
    @State private var message = ""
    @State private var didSubmitMove = false
    @State private var isDuelPhaseActive = false
    @State private var shouldGoToReadyView = false
    @State private var hasSentWinnerDisplayed = false
    @State private var hasDismissed = false
    @State private var matchStarted = false
    @State private var navigateToReadyView = false
    @State private var showVictory = false
    
    @State private var penaltyCountdown = 0
    @State private var isPenaltyPhase = true
    @State private var showPenaltyOverlay = false
    @State private var penaltyResultMessage = ""
    
    var body: some View {
        ZStack {
            backgroundGradient
            fingerDetectionLayer
            roundStatusOverlay
            
            if showForfeitOverlay {
                forfeitedOverlay(text: message)
            }
            
            if isPenaltyPhase {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    Text("Get Ready...\n\(penaltyCountdown)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .allowsHitTesting(false)
                .zIndex(2)
            }
            
            if showPenaltyOverlay {
                forfeitedOverlay(text: penaltyResultMessage)
                    .zIndex(3)
            }
            
            if gameManager.currentPhase == .winner,
               let winState = gameManager.playerWinState {
                if !showPenaltyOverlay && !showForfeitOverlay {
                    winnerOverlay(for: winState)
                        .ignoresSafeArea()
                        .zIndex(4)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToReadyView) {
            GameReadyView(
                firestore: firestore,
                gameManager: gameManager,
                onCountdownComplete: onRoundComplete,
                shouldGoToReadyView: $shouldGoToReadyView
            )
        }
        .fullScreenCover(isPresented: $showVictory) {
            VictoryView(
                result: gameManager.overallWinner ?? "tie",
                onDismissToLobby: {
                    print("🎯 VictoryView callback triggered. Returning to lobby from GameView.")
                    onRoundComplete()
                    dismissToLobby()
                }
            )
        }
        .onAppear(perform: handleOnAppear)
        .onChange(of: gameManager.overallWinner) { _, newValue in
            handleOverallWinnerChange(newValue)
        }
        .onChange(of: firestore.signal) { _, newValue in
            handleSignal(newValue)
        }
        .onChange(of: gameManager.currentPhase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onChange(of: gameManager.winnerThisRound) { _, winner in
            handleRoundWinner(winner)
        }
        .onChange(of: shouldGoToReadyView) { _, shouldAdvance in
            handleRoundAdvance(shouldAdvance)
        }
        .onDisappear(perform: handleDisappear)
        .navigationBarBackButtonHidden(true)
    }
}

private extension GameView {
    var backgroundGradient: some View {
        Group {
            switch fingerCount {
            case 1:
                SpriteView(scene: TriangleBackground(size: UIScreen.main.bounds.size))
            case 2:
                SpriteView(scene: SquareBackground(size: UIScreen.main.bounds.size))
            case 3:
                SpriteView(scene: CircleBackground(size: UIScreen.main.bounds.size))
            default:
                SpriteView(scene: GameViewBackground(size: UIScreen.main.bounds.size))
            }
        }
        .ignoresSafeArea()
    }
    
    var isShapeBackgroundActive: Bool {
        return fingerCount == 1 || fingerCount == 2 || fingerCount == 3
    }
    
    var fingerDetectionLayer: some View {
        FingerTapViewRepresentable { count in
            print("🖐 Detected finger tap count: \(count)")
            
            guard !didSubmitMove else { return }
            
            if isPenaltyPhase {
                print("❌ Early tap detected during penalty phase.")
                handleEarlyTap()
                return
            }
            
            if (1...3).contains(count) {
                fingerCount = count
                message = ""
                if isDuelPhaseActive, gameManager.playerMove == nil,
                   let move = RPSMove(rawValue: count) {
                    gameManager.submitMove(move)
                    didSubmitMove = true
                }
            } else {
                fingerCount = 0
                message = "Invalid number of fingers"
            }
        }
        .id("round-\(gameManager.currentRound)")
        .ignoresSafeArea()
    }
    
    var roundStatusOverlay: some View {
        VStack {
            HStack {
                CustomLobbyButton(title: "Forfeit", color: Color("pencilRed")) {
                    handleForfeit()
                }

                Spacer()
            }
            .padding([.top, .horizontal])
            
            Spacer()
            
            if !isShapeBackgroundActive {
                Text("Round \(gameManager.currentRound) of 7")
                    .font(.custom("DK Lemon Yellow Sun", size: 26))
                    .foregroundColor(Color("pencilYellow"))
                    .padding(.bottom, 8)
            }
            
            if !message.isEmpty && !showForfeitOverlay {
                Text(message)
                    .foregroundColor(.red)
                    .font(.headline)
            }
            
            Spacer()
        }
    }
}

private extension GameView {
    func handleForfeit() {
        print("🏳️ Player tapped forfeit.")
        didForfeit = true
        isWinner = false
        message = "Player forfeited. Returning to lobby."
        showForfeitOverlay = true
        firestore.forfeitMatch()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exitMatchAndReturnToLobby()
        }
    }
    
    func handleOnAppear() {
        print("🚀 GameView onAppear fired")
        print("""
        🧪 [ROUND CHECK]
        - userID = \(firestore.currentUserID)
        - isHost = \(firestore.isHost)
        - currentRound = \(gameManager.currentRound)
        - lastSyncedRound = \(gameManager.lastSyncedRound)
        - hasIncrementedRound = \(gameManager.hasIncrementedRound)
        """)
        
        MusicManager.shared.playGameMusic()
        firestore.clearStartMatchSignal()
        
        gameManager.winnerThisRound = nil
        gameManager.playerMove = nil
        firestore.hasSentMove = false
        isDuelPhaseActive = true
        
        if gameManager.currentRound == 1 {
            matchStarted = false
        }
        
        navigateToReadyView = false
        shouldGoToReadyView = false
        resetForNextRound()
        
        if firestore.sessionID.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !hasDismissed {
                    hasDismissed = true
                    onRoundComplete()
                    dismissToLobby()
                }
            }
        }
        
        firestore.recordDuelStartTime()
        if firestore.isHost && gameManager.currentRound < 7 {
            print("👑 Host detected. Checking if round should be incremented.")
            
            if !gameManager.hasIncrementedRound &&
                gameManager.currentRound == gameManager.lastSyncedRound {
                
                gameManager.hasIncrementedRound = true
                firestore.incrementRoundNumber()
                print("🔁 ✅ Host incremented round on GameView appear.")
            } else {
                print("⛔️ Skipped round increment by host: Already incremented or round mismatch.")
            }
        } else {
            print("🙅‍♂️ Not host or max round reached — skipping round increment.")
        }
        
        firestore.fetchPenaltyCountdown { value in
            if let value = value {
                penaltyCountdown = value
                isPenaltyPhase = true
                startPenaltyTimer()
            } else {
                print("⚠️ No penalty countdown found. Skipping penalty phase.")
                isPenaltyPhase = false
            }
        }
    }
    
    func handleEarlyTap() {
        didSubmitMove = true
        isDuelPhaseActive = false
        
        gameManager.winnerThisRound = "opponent"
        gameManager.opponentScore += 100
        gameManager.playerWinState = .earlyTap
        gameManager.roundResults.append(.earlyTap)
        
        firestore.sendSignal("EARLY_TAP_BY_\(firestore.currentUserID)")
    }
    
    func startPenaltyTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if penaltyCountdown > 0 {
                penaltyCountdown -= 1
            } else {
                timer.invalidate()
                isPenaltyPhase = false
                print("✅ Penalty phase ended. Players can now tap.")
                startDuelTimeoutTimer()
            }
        }
    }
    
    func handleOverallWinnerChange(_ newValue: String?) {
        guard newValue != nil, !showVictory else { return }
        showVictory = true
    }
    
    func handleSignal(_ newSignal: String) {
        guard firestore.gameStatus == "active" else { return }
        
        switch newSignal {
        case "START_MATCH":
            if !matchStarted {
                matchStarted = true
                isDuelPhaseActive = true
                gameManager.currentPhase = .duel
                resetForNextRound()
            }
            
        case let sig where sig.starts(with: "FORFEIT_BY_"):
            let forfeitingPlayer = sig.replacingOccurrences(of: "FORFEIT_BY_", with: "")
            isWinner = (forfeitingPlayer != firestore.currentUserID)
            message = isWinner ? "Opponent forfeited. \nYou are the Winner!" : "Player forfeited. \nReturning to Lobby..."
            showForfeitOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exitMatchAndReturnToLobby()
            }
            
        case let sig where sig.starts(with: "EARLY_TAP_BY_"):
            let earlyTapper = sig.replacingOccurrences(of: "EARLY_TAP_BY_", with: "")
            if earlyTapper != firestore.currentUserID {
                print("🎯 Opponent tapped too early! You win the round.")
                gameManager.winnerThisRound = "player"
                gameManager.playerScore += 100
                gameManager.playerWinState = .win
                gameManager.roundResults.append(.win)
                penaltyResultMessage = "😲 The opponent clicked too early.\nYou win the round!"
                showPenaltyOverlay = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    gameManager.notifyWinnerDisplayed()
                    showPenaltyOverlay = false
                }
            }
            
        case "ADVANCE_ROUND":
            isDuelPhaseActive = false
            resetForNextRound()
            
        case "NEXT_ROUND":
            shouldGoToReadyView = true
            
        case "OPPONENT_DISCONNECTED":
            gameManager.overallWinner = "disconnect"
            gameManager.currentPhase = .victory
            showVictory = true
            
        default:
            break
        }
    }
    
    func startDuelTimeoutTimer() {
        let roundAtStart = gameManager.currentRound
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            guard gameManager.currentRound == roundAtStart else {
                print("⏹ Duel timeout skipped due to round change.")
                return
            }
            
            guard gameManager.winnerThisRound == nil else {
                print("⏹ Duel timeout skipped — winner already declared.")
                return
            }
            
            print("⏰ Timeout — checking if both players submitted.")
            let playerSubmitted = didSubmitMove
            
            firestore.fetchOpponentMove { opponentMove in
                let opponentSubmitted = opponentMove != nil
                
                if !playerSubmitted || !opponentSubmitted {
                    gameManager.transitionToWinnerPhase(winnerName: "tie")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        gameManager.notifyWinnerDisplayed()
                    }
                } else {
                    print("✅ Both players actually submitted. Timeout aborted.")
                }
            }
        }
    }
    
    func handlePhaseChange(_ phase: GamePhase) {
        if phase == .duel {
            fingerCount = 0
            didSubmitMove = false
            message = ""
            hasSentWinnerDisplayed = false
        }
    }
    
    func handleRoundWinner(_ winner: String?) {
        guard winner != nil else { return }
        
        if gameManager.currentPhase != .winner {
            gameManager.currentPhase = .winner
        }
        
        if !hasSentWinnerDisplayed {
            hasSentWinnerDisplayed = true
            
            let shouldDelay = [
                .win,
                .lose,
                .tie,
                .earlyTap
            ].contains(gameManager.playerWinState)
            
            let delay: Double = shouldDelay ? 3 : 0
            
            print("🕒 Waiting \(delay)s before notifying winnerDisplayed. Reason: \(String(describing: gameManager.playerWinState))")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                gameManager.notifyWinnerDisplayed()
            }
        }
    }
    
    func handleRoundAdvance(_ shouldAdvance: Bool) {
        if shouldAdvance {
            if gameManager.currentRound < 7 {
                navigateToReadyView = true
            } else {
                let result = (gameManager.playerScore > gameManager.opponentScore) ? "player"
                : (gameManager.playerScore < gameManager.opponentScore) ? "opponent"
                : "tie"
                gameManager.overallWinner = result
                gameManager.currentPhase = .victory
                showVictory = true
            }
        }
    }
    
    func handleDisappear() {
        if MusicManager.shared.currentTrackName == "Game.wav" {
            MusicManager.shared.stopMusic()
        }
        
        shouldGoToReadyView = false
    }
    
    func resetForNextRound() {
        gameManager.winnerThisRound = nil
        gameManager.playerMove = nil
        isDuelPhaseActive = true
        gameManager.currentPhase = .duel
        didSubmitMove = false
        fingerCount = 0
        message = ""
        penaltyResultMessage = ""
        hasSentWinnerDisplayed = false
        gameManager.hasAdvancedRound = false
    }
    
    func exitMatchAndReturnToLobby() {
        firestore.stopListening()
        firestore.autoMatchEnabled = false
        MusicManager.shared.stopMusic()
        
        if !hasDismissed {
            hasDismissed = true
            onRoundComplete()
            dismissToLobby()
        }
    }
    
    func forfeitedOverlay(text: String) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(text)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .font(.title2.bold())
                    .padding()
            }
            .padding()
        }
    }
    
    func winnerOverlay(for reason: playerWinState) -> some View {
        let text: String
        switch reason {
        case .win:
            text = "Congratulations! \n😎 You've won the round!"
        case .lose:
            text = "Sorry... \n😢 but you've lost the round."
        case .tie:
            text = "It seems like at least one of you did not submit moves... 😢 No winners this round."
        case .earlyTap:
            text = "😢 You clicked too early! The round is lost."
        }
        
        return AnyView(
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack {
                    Text(text)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .font(.title2.bold())
                        .padding()
                }
            }
        )
    }
}

