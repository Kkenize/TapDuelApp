//
//  LobbyView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/24/25.
//

import SwiftUI
import FirebaseFirestore
import AVFAudio
import SpriteKit

struct LobbyView: View {
    @StateObject var firestore = FirestoreManager.shared
    @State private var showSettings = false
    @State private var showCreatePopup = false
    @State private var showJoinPopup = false
    @State private var createdRoomCode: String = ""
    @State private var joinCode: String = ""
    @State private var volume: Double = 0.5
    @State private var isMuted: Bool = false
    @State private var navigateToGame = false
    @State private var hasStartedSearch = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showMatchFoundMessage = false
    @State private var bounce = false
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                mainLobbyContent
                topRightButtons
                settingsPopup
                createRoomPopup
                joinRoomPopup
            }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .onChange(of: firestore.isConnected) { _, isConnected in
                if isConnected {
                    if !showMatchFoundMessage {
                        hasStartedSearch = false
                        showMatchFoundMessage = true
                        print("✅ Match Found! Displaying message...")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if firestore.isConnected {
                                showMatchFoundMessage = false
                                navigateToGame = true
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToGame) {
                GameHomeView(
                    firestore: firestore,
                    onMatchOver: {
                        resetLobbyAfterMatch()
                    }
                )
            }
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                MusicManager.shared.resumeIfNeeded()
            }
        }
    }

    private var backgroundGradient: some View {
        SpriteView(scene: LobbyViewBackground(size: UIScreen.main.bounds.size))
            .ignoresSafeArea()
    }

    private var mainLobbyContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Tap Duel")
                .font(.custom("DK Lemon Yellow Sun", size: 100))
                .foregroundColor(Color("pencilYellow"))
                .shadow(color: .black.opacity(0.25), radius: 2, x: 1, y: 1)

            ZStack {
                Text("Match found! Launching game…")
                    .font(.custom("DK Lemon Yellow Sun", size: 30))
                    .opacity(0)

                if hasStartedSearch {
                    VStack(spacing: 4) {
                        Text("Searching for opponent…")
                            .font(.custom("DK Lemon Yellow Sun", size: 30))
                            .foregroundColor(Color("pencilYellow"))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)

                        Button("Cancel") {
                            firestore.autoMatchEnabled = false
                            hasStartedSearch = false
                            firestore.cleanupMyRooms()
                            bounce = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    bounce = true
                                }
                        }
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                        .foregroundColor(Color("pencilYellow").opacity(0.8))
                    }
                } else if showMatchFoundMessage {
                    Text("Match found! Launching game…")
                        .font(.custom("DK Lemon Yellow Sun", size: 30))
                        .foregroundColor(Color("pencilYellow"))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                } else if !firestore.isConnected {
                    Button(action: startRandomMatch) {
                        Text("Random Match?")
                            .font(.custom("DK Lemon Yellow Sun", size: 30))
                            .foregroundColor(Color("pencilYellow"))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0.5, y: 0.5)
                            .scaleEffect(bounce ? 1.05 : 0.95)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: bounce)
                            .onAppear { bounce = true }
                    }
                }
            }
            .frame(height: 80)
            .padding(.top, -30)

            Spacer()
        }
        .padding()
    }

    private var topRightButtons: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()

                CustomLobbyButton(title: "Create", color: .green) {
                    if !createdRoomCode.isEmpty {
                        firestore.deleteRoom(code: createdRoomCode)
                    }
                    createdRoomCode = firestore.createPrivateRoom()
                    showCreatePopup = true
                }

                CustomLobbyButton(title: "Join", color: .blue) {
                    showJoinPopup = true
                }

                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(Color.gray.opacity(0.6))
                        .overlay(
                            Image("LightSketchTexture")
                                .resizable(resizingMode: .tile)
                                .opacity(0.25)
                                .blendMode(.multiply)
                                .clipShape(Circle())
                        )
                        .padding(10)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var settingsPopup: some View {
        Group {
            if showSettings {
                SettingsPopupView(
                    isPresented: $showSettings,
                    volume: $volume,
                    isMuted: $isMuted,
                    playerID: firestore.currentUserID
                )
            }
        }
    }

    private var createRoomPopup: some View {
        Group {
            if showCreatePopup {
                VStack(spacing: 20) {
                    DismissButton {
                        showCreatePopup = false
                        firestore.cleanupMyRooms()
                    }

                    Text("Create Room Success!")
                        .font(.custom("DK Lemon Yellow Sun", size: 34))
                        .foregroundColor(Color("pencilYellow"))

                    Text("Your room code is:")
                        .font(.custom("DK Lemon Yellow Sun", size: 24))
                        .foregroundColor(Color("pencilYellow"))

                    Text(createdRoomCode)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color("pencilYellow"))
                        .padding(.vertical, 8)
                }
                .padding()
                .frame(maxWidth: 300)
                .background(
                    ZStack {
                        Color(white: 0.95)
                        Image("45DegreeFabricLight")
                            .resizable(resizingMode: .tile)
                            .opacity(0.15)
                    }
                )
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
    }
    
    private var joinRoomPopup: some View {
        Group {
            if showJoinPopup {
                VStack(spacing: 20) {
                    DismissButton {
                        showJoinPopup = false
                    }

                    Text("Enter Room Code")
                        .font(.custom("DK Lemon Yellow Sun", size: 34))
                        .foregroundColor(Color("pencilYellow"))

                    TextField("e.g. ABC123", text: $joinCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .frame(width: 200)
                        .onChange(of: joinCode) { _, newValue in
                            if newValue.count > 6 {
                                joinCode = String(newValue.prefix(6))
                            }
                        }

                    HStack(spacing: 16) {
                        Button("Clear") {
                            joinCode = ""
                        }
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color("pencilYellow").opacity(0.2))
                        .foregroundColor(Color("pencilYellow"))
                        .cornerRadius(10)

                        Button("Join") {
                            tryJoinRoom()
                        }
                        .disabled(joinCode.isEmpty)
                        .opacity(joinCode.isEmpty ? 0.5 : 1.0)
                        .font(.custom("DK Lemon Yellow Sun", size: 20))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color("pencilYellow").opacity(0.2))
                        .foregroundColor(Color("pencilYellow"))
                        .cornerRadius(10)
                    }
                }
                .padding()
                .frame(maxWidth: 300)
                .background(
                    ZStack {
                        Color(white: 0.95)
                        Image("45DegreeFabricLight")
                            .resizable(resizingMode: .tile)
                            .opacity(0.15)
                    }
                )
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
    }

    private func startRandomMatch() {
        if !createdRoomCode.isEmpty {
            firestore.deleteRoom(code: createdRoomCode)
            createdRoomCode = ""
        }
        firestore.autoMatchEnabled = true
        firestore.connect()
        hasStartedSearch = true
    }

    private func tryJoinRoom() {
        let trimmed = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = "^[A-Z0-9]{6}$"
        let isValid = NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: trimmed)

        guard isValid else {
            alertMessage = "Invalid room code."
            showAlert = true
            return
        }

        if !createdRoomCode.isEmpty {
            firestore.deleteRoom(code: createdRoomCode)
            createdRoomCode = ""
        }

        firestore.joinPrivateRoom(code: trimmed) { error in
            if error == nil {
                showJoinPopup = false
            } else {
                alertMessage = error?.localizedDescription ?? "Unknown error joining room"
                showAlert = true
            }
        }
    }

    private func handleAppear() {
        print("🎮 LobbyView appeared. Starting fresh.")
        MusicManager.shared.setMuted(isMuted)
        MusicManager.shared.setVolume(Float(volume))
        MusicManager.shared.playLobbyMusic()

        hasStartedSearch = false
        showMatchFoundMessage = false
        firestore.forceDisconnect()
    }

    private func handleDisappear() {
        MusicManager.shared.stopMusic()
    }

    private func resetLobbyAfterMatch() {
        print("🧼 Resetting lobby after match (but not resetting FirestoreManager yet).")

        hasStartedSearch = false
        firestore.isConnected = false
        firestore.autoMatchEnabled = false
        firestore.signal = ""
        navigateToGame = false
    }
}


#Preview {
    LobbyView()
}

