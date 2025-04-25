//
//  GameCenterMatchmakerView.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/22/25.
//

import Foundation
import SwiftUI
import GameKit

struct GameCenterMatchmakerView: UIViewControllerRepresentable {
    var onMatchFound: (GKMatch) -> Void

    func makeCoordinator() -> GameCenterMultiplayerCoordinator {
        return GameCenterMultiplayerCoordinator(onMatchFound: onMatchFound)
    }

    func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        let mmvc = GKMatchmakerViewController(matchRequest: request)!
        mmvc.matchmakerDelegate = context.coordinator
        return mmvc
    }

    func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) {}
}
