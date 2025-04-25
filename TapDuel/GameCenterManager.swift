//
//  GameCenterManager.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/22/25.
//

import Foundation
import FirebaseFirestore
import GameKit

class GameCenterManager: NSObject, ObservableObject, GKMatchmakerViewControllerDelegate, GKLocalPlayerListener {
    
    static let shared = GameCenterManager()
    var inviteCompletion: (([GKPlayer]) -> Void)?

    func authenticate() {
        let localPlayer = GKLocalPlayer.local
        localPlayer.authenticateHandler = { viewController, error in
            if let vc = viewController {
                if let rootVC = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first?.rootViewController {
                    rootVC.present(vc, animated: true)
                }
            } else if localPlayer.isAuthenticated {
                print("✅ Game Center authenticated: \(localPlayer.displayName)")
                localPlayer.register(self)
            } else {
                print("❌ Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    func presentInviteFriendUI(completion: @escaping ([GKPlayer]) -> Void) {
        guard GKLocalPlayer.local.isAuthenticated else {
            print("❌ Player not authenticated.")
            return
        }

        inviteCompletion = completion
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        let mmvc = GKMatchmakerViewController(matchRequest: request)
        mmvc?.matchmakerDelegate = self

        if let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController,
           let matchVC = mmvc {
            rootVC.present(matchVC, animated: true)
        }
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        print("✅ Match found with players: \(match.players.map(\.displayName))")
        viewController.dismiss(animated: true)

        guard match.players.count == 1 else {
            print("⚠️ Waiting for friend to join...")
            return
        }
        
        let localDisplayName = GKLocalPlayer.local.displayName
        let friend = match.players.first!
        let friendDisplayName = friend.displayName
        
        let allNames = [localDisplayName, friendDisplayName].sorted()
        let combinedCode = allNames.joined(separator: "-").replacingOccurrences(of: " ", with: "")
        print("🧩 Room code based on players: \(combinedCode)")
        
        let firestore = FirestoreManager.shared
        
        let isHost = localDisplayName == allNames.first

        if isHost {
            print("👑 Acting as host. Creating private room.")
            firestore.sessionID = combinedCode
            firestore.didCreateCurrentRoom = true
            firestore.isHost = true

            firestore.db.collection("games").document(combinedCode).setData([
                "state": "waiting",
                "signal": "",
                "gameStatus": "active",
                "private": true,
                "creatorID": firestore.currentUserID,
                "player1": firestore.currentUserID,
                "player1Name": localDisplayName,
                "round_number": 1,
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Failed to create room: \(error)")
                    return
                }
                print("✅ Private Firebase room created.")
                firestore.listenForUpdates()
                firestore.startHeartbeat()
                DispatchQueue.main.async {
                    firestore.isConnected = true
                }
            }
        } else {
            print("🧭 Acting as guest. Joining private room.")
            firestore.sessionID = combinedCode
            firestore.didCreateCurrentRoom = false
            firestore.isHost = false

            let ref = firestore.db.collection("games").document(combinedCode)
            ref.getDocument { snapshot, error in
                if let doc = snapshot, doc.exists {
                    ref.updateData([
                        "player2": firestore.currentUserID,
                        "player2Name": localDisplayName,
                        "state": "connected"
                    ]) { err in
                        if let err = err {
                            print("❌ Failed to join room: \(err)")
                        } else {
                            print("✅ Joined private Firebase room.")
                            firestore.listenForUpdates()
                            firestore.startHeartbeat()
                            DispatchQueue.main.async {
                                firestore.isConnected = true
                            }
                        }
                    }
                } else {
                    print("❌ Room not found. Host may not have created it yet.")
                }
            }
        }
    }
    
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        print("❌ Invite cancelled.")
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        print("❌ Matchmaker error: \(error.localizedDescription)")
        viewController.dismiss(animated: true)
    }
    
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("📨 Received invite from \(player.displayName)")
        let mmvc = GKMatchmakerViewController(invite: invite)
        mmvc?.matchmakerDelegate = self

        if let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController,
           let matchVC = mmvc {
            rootVC.present(matchVC, animated: true)
        }
    }
}

class GameCenterMatchHandler: NSObject, GKMatchDelegate {
    var match: GKMatch?

    func startListening(for match: GKMatch) {
        self.match = match
        self.match?.delegate = self
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        //TODO: future updates for v1.0.1
    }
}


