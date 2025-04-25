//
//  GameManager.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import Foundation
import Combine

enum GamePhase {
    case ready
    case countdown
    case duel
    case winner
    case victory
}

enum RPSMove: Int, Codable {
    case one = 1
    case two = 2
    case three = 3
}

enum playerWinState {
    case win
    case lose
    case tie
    case earlyTap
}

class GameManager: ObservableObject {
    @Published var currentPhase: GamePhase = .duel
    @Published var currentRound: Int = 1
    @Published var playerScore: Int = 0
    @Published var opponentScore: Int = 0
    @Published var playerMove: RPSMove? = nil
    @Published var opponentMove: RPSMove? = nil
    @Published var winnerThisRound: String? = nil
    @Published var overallWinner: String?
    @Published var hasIncrementedRound: Bool = false
    @Published var lastSyncedRound: Int = 0
    @Published var playerWinState: playerWinState? = nil
    @Published var roundResults: [playerWinState] = []

    private let firestore: FirestoreManager
    private let roomCode: String

    private let maxRounds = 7
    var hasAdvancedRound = false

    init(firestore: FirestoreManager, roomCode: String) {
        self.firestore = firestore
        self.roomCode = roomCode

        observeStartMatchSignal()
        observeWinner()
        observeAdvanceRoundSignal()
        observeVictoryResult()
    }

    func resetGame() {
        print("🧼 Resetting full GameManager state")
        currentPhase = .duel
        playerScore = 0
        opponentScore = 0
        playerMove = nil
        firestore.updateRoundNumber(1)
        opponentMove = nil
        roundResults = []
        winnerThisRound = nil
    }

    func sendStartMatchRequest() {
        print("📡 Sending START_MATCH request")
        firestore.requestStartMatch()
    }

    func startMatch() {
        print("🚦 Starting duel phase")
        resetMoves()
        resetWinner()
        hasAdvancedRound = false
        firestore.hasSentMove = false 
        currentPhase = .duel
        firestore.fetchRoundNumber { [weak self] round in
            DispatchQueue.main.async {
                self?.currentRound = round ?? 1
            }
        }
    }
    
    func transitionToWinnerPhase(winnerName: String?) {
        print("🎯 Transitioning to WINNER phase. Winner: \(winnerName ?? "nil")")

        if winnerThisRound != nil {
            print("⚠️ Winner already set to \(winnerThisRound!). Skipping transition.")
            return
        }

        currentPhase = .winner
        winnerThisRound = winnerName

        if let winner = winnerName {
            switch winner {
            case "player":
                playerScore += 100
                playerWinState = .win
                roundResults.append(.win)
                print("🟢 Player win added to roundResults.")

            case "opponent":
                opponentScore += 100
                playerWinState = .lose
                roundResults.append(.lose)
                print("🔴 Player loss added to roundResults.")

            case "tie":
                playerWinState = .tie
                roundResults.append(.tie)
                print("🤝 Tie added to roundResults.")

            default:
                print("❓ Unrecognized winner name: \(winner)")
            }
        } else {
            print("❓ Winner name was nil. This shouldn't happen.")
        }
    }

    func notifyWinnerDisplayed() {
        print("📬 Winner displayed. Notifying Firestore")
        firestore.markWinnerDisplayed()
    }

    private func advanceToNextRound() {
        guard !hasAdvancedRound else {
            print("⚠️ Already advanced round. Skipping duplicate call.")
            return
        }
        hasAdvancedRound = true

        print("➡️ Advancing to next round (current: \(currentRound))")

        if currentRound < maxRounds {
            DispatchQueue.main.async {
                self.currentPhase = .ready
            }
        } else {
            print("🏁 Max round reached. Evaluating final score.")
            evaluateFinalScore()
        }
    }
    
    private func resetWinner() {
        winnerThisRound = nil
    }

    private func resetMoves() {
        playerMove = nil
        opponentMove = nil
    }

    private func evaluateFinalScore() {
        print("🏁 Final Score Check")
        currentPhase = .victory
        firestore.sendVictorySignal()
    }

    func submitMove(_ move: RPSMove) {
        guard playerMove == nil else {
            print("⚠️ Move already submitted. Ignoring duplicate.")
            return
        }
        print("📤 Submitting move: \(move)")
        playerMove = move
        firestore.sendMove(move)
    }

    private func observeStartMatchSignal() {
        firestore.onPhaseUpdate = { [weak self] signal in
            DispatchQueue.main.async {
                if signal == "START_MATCH", self?.currentPhase != .duel {
                    self?.startMatch()
                }
            }
        }
    }

    private func observeWinner() {
        firestore.onWinnerResultReceived = { [weak self] result in
            DispatchQueue.main.async {
                self?.transitionToWinnerPhase(winnerName: result)
            }
        }
    }

    private func observeAdvanceRoundSignal() {
        firestore.onSignalUpdate = { [weak self] signal in
            DispatchQueue.main.async {
                if signal == "NEXT_ROUND" {
                    print("🔄 Received NEXT_ROUND signal.")
                    self?.advanceToNextRound()
                }
            }
        }
    }
    
    private func observeVictoryResult() {
        firestore.onVictoryResultReceived = { [weak self] victor in
            DispatchQueue.main.async {
                print("🏆 Victory result received from Firestore: \(victor)")
                self?.handleVictoryResult(victor)
            }
        }
    }
    
    private func handleVictoryResult(_ victor: String) {
        currentPhase = .victory
        overallWinner = victor 
    }
}
