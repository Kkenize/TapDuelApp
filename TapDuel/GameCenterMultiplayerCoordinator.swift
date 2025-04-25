//
//  GameCenterMultiplayerCoordinator.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/22/25.
//

import Foundation
import GameKit
import SwiftUI

class GameCenterMultiplayerCoordinator: NSObject, GKMatchmakerViewControllerDelegate {
    let onMatchFound: (GKMatch) -> Void

    init(onMatchFound: @escaping (GKMatch) -> Void) {
        self.onMatchFound = onMatchFound
    }

    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        print("❌ Game Center matchmaking failed: \(error.localizedDescription)")
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        print("✅ Match found with players: \(match.players)")
        viewController.dismiss(animated: true)
        onMatchFound(match)
    }
}
