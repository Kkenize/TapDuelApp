//
//  GameHomeView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/27/25.
//

import SwiftUI
import FirebaseFirestore
import SpriteKit

struct GameHomeView: View {
    @ObservedObject var firestore: FirestoreManager
    var onMatchOver: () -> Void
    
    @State private var showConfirmView = false
    @State private var timedOut = false
    @State private var rejectionListener: ListenerRegistration?
    
    var body: some View {
        ZStack {
            SpriteView(scene: GameHomeViewBackground(size: UIScreen.main.bounds.size))
                .ignoresSafeArea()
            
            if showConfirmView {
                GameConfirmView(
                    firestore: firestore,
                    onMatchOver: onMatchOver
                )
                .transition(.opacity)
                
            } else if timedOut {
                VStack(spacing: 24) {
                    Text("Player did not confirm.\nReturning to lobby.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("pencilYellow"))
                        .font(.custom("DK Lemon Yellow Sun", size: 80))
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)

                    Text("Tap anywhere to return to the lobby")
                        .foregroundColor(Color("pencilYellow").opacity(0.7))
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                }
                .padding()
                .onTapGesture {
                    firestore.closeGameRoom()
                    firestore.autoMatchEnabled = false
                    onMatchOver()
                }
                
            } else {
                VStack(spacing: 16) {
                    Text("Get Ready!")
                        .font(.custom("DK Lemon Yellow Sun", size: 80))
                        .foregroundColor(Color("pencilYellow"))
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)

                    Text("Tap anywhere to enter the arena")
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                        .foregroundColor(Color("pencilYellow").opacity(0.85))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                }
                .onTapGesture {
                    showConfirmView = true
                }
                .contentShape(Rectangle())
            }
        }
        .onAppear {
            print("✅ Entered GameHomeView with sessionID: \(firestore.sessionID)")
            listenForRejection()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                if !showConfirmView {
                    firestore.checkIfOtherConfirmed { otherConfirmed in
                        print("🤔 Other player confirmed? \(otherConfirmed)")
                        if !otherConfirmed && firestore.isConnected {
                            firestore.markRejection(reason: "double_timeout")
                            timedOut = true
                        }
                    }
                }
            }
        }
        .onDisappear {
            rejectionListener?.remove()
        }
        .navigationBarBackButtonHidden(true)
    }
    
    func listenForRejection() {
        let docRef = Firestore.firestore().collection("games").document(firestore.sessionID)
        rejectionListener = docRef.addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(), error == nil else { return }
            
            if let rejection = data["rejection_reason"] as? String {
                if rejection == "timeout" {
                    print("📩 Rejection signal received: \(rejection)")
                    DispatchQueue.main.async {
                        timedOut = true
                    }
                } else if rejection == "double_timeout" {
                    print("📩 Rejection signal received: \(rejection)")
                    DispatchQueue.main.async {
                        timedOut = true
                    }
                }
            }
        }
    }
}

