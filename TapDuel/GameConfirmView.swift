//
//  GameConfirmView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import SwiftUI
import FirebaseFirestore
import SpriteKit

struct GameConfirmView: View {
    @ObservedObject var firestore: FirestoreManager
    var onMatchOver: () -> Void
    
    @StateObject private var gameManager: GameManager
    
    @State private var dataListener: ListenerRegistration?
    @State private var bothConfirmed = false
    @State private var showReadyView = false
    @State private var showRejectionScreen = false
    @State private var rejectionMessage: String? = nil
    @State private var opponentConfirmed = false
    @State private var pendingPhase: String? = nil
    
    @State private var shouldGoToReadyView = false
    
    let confirmWaitLimit: TimeInterval = 10
    let jointStartDelay: TimeInterval = 3
    
    init(firestore: FirestoreManager, onMatchOver: @escaping () -> Void) {
        self.firestore = firestore
        self.onMatchOver = onMatchOver
        _gameManager = StateObject(wrappedValue: GameManager(
            firestore: firestore,
            roomCode: firestore.sessionID
        ))
    }
    
    var body: some View {
        ZStack {
            SpriteView(scene: GameConfirmViewBackground(size: UIScreen.main.bounds.size))
                .ignoresSafeArea()
            
            if showReadyView {
                GameReadyView(
                    firestore: firestore,
                    gameManager: gameManager,
                    onCountdownComplete: {
                        showReadyView = false
                    },
                    shouldGoToReadyView: $shouldGoToReadyView
                )
                .transition(.opacity)
            } else if let rejectionMessage = rejectionMessage {
                VStack(spacing: 24) {
                    Text(rejectionMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("pencilYellow"))
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)
                        .padding()

                    Text("Tap anywhere to return to the lobby")
                        .foregroundColor(Color("pencilYellow").opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .font(.custom("DK Lemon Yellow Sun", size: 30))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                }
                .padding()
                .onTapGesture {
                    firestore.closeGameRoom()
                    firestore.autoMatchEnabled = false
                }
            } else {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color("pencilBlue"), lineWidth: 12)
                            .frame(width: 180, height: 180)
                            .overlay(
                                Image("LightSketchTexture")
                                    .resizable(resizingMode: .tile)
                                    .opacity(0.15)
                                    .blendMode(.multiply)
                                    .clipShape(Circle())
                            )

                        Image(systemName: "checkmark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(Color("pencilGreen"))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 1, y: 1)
                    }
                    .padding(.bottom, 10)
                    
                    Text("Player Confirmed!")
                        .font(.custom("DK Lemon Yellow Sun", size: 40))
                        .foregroundColor(Color("pencilYellow"))
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 1, y: 1)

                    Text("Waiting for the other player...")
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                        .foregroundColor(Color("pencilYellow").opacity(0.8))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                }
            }
        }
        .onAppear {
            print("👀 GameConfirmView appeared.")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                firestore.markEnteredConfirmView()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                firestore.confirmPlayerReady()
            }
            
            startListeningForConfirmation()
            startTimeoutTimer()
            
            firestore.onPhaseUpdate = { phase in
                print("📡 Received Firestore phase: \(phase)")
                if phase == "CONFIRMED" {
                    if showReadyView {
                        print("✅ Showing ReadyView immediately.")
                        showReadyView = true
                    } else {
                        print("📦 Queuing CONFIRMED phase for after UI is ready.")
                        pendingPhase = "CONFIRMED"
                    }
                }
            }
        }
        .onChange(of: showReadyView) { _, visible in
            if visible, pendingPhase == "CONFIRMED" {
                print("📦 Handling queued CONFIRMED signal now.")
                showReadyView = true
                pendingPhase = nil
            }
        }
        .onDisappear {
            dataListener?.remove()
        }
        .navigationBarBackButtonHidden(true)
    }
    
    func startListeningForConfirmation() {
        let docRef = Firestore.firestore().collection("games").document(firestore.sessionID)
        dataListener = docRef.addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(), error == nil else { return }
            
            let myKey = "confirmed_\(firestore.currentUserID)"
            let otherKey = data.keys.first(where: { $0.hasPrefix("confirmed_") && $0 != myKey })
            
            let iConfirmed = data[myKey] as? Bool ?? false
            let theyConfirmed = otherKey != nil ? (data[otherKey!] as? Bool ?? false) : false
            opponentConfirmed = theyConfirmed
            
            if let rejection = data["rejection_reason"] as? String {
                DispatchQueue.main.async {
                    if rejection == "timeout" {
                        rejectionMessage = "Sorry, your opponent did not confirm.\nReturning to lobby."
                    } else if rejection == "double_timeout" {
                        rejectionMessage = "Both players failed to confirm.\nReturning to lobby."
                    }
                    showRejectionScreen = true
                }
                return
            }
            
            if iConfirmed && theyConfirmed && !bothConfirmed {
                bothConfirmed = true
                firestore.tryStartMatchIfBothConfirmed()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + jointStartDelay) {
                    showReadyView = true
                }
            }
        }
    }
    
    func startTimeoutTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmWaitLimit) {
            guard !bothConfirmed else { return }
            firestore.markRejection(reason: "timeout")
        }
    }
}

