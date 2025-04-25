//
//  FirestoreManager.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/24/25.
//

import Foundation
import GameKit
import FirebaseFirestore

class FirestoreManager: ObservableObject {
    static let shared = FirestoreManager()
    let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var heartbeatTimer: Timer?
    var hasSentMove = false
    
    let currentUserID: String = {
        if let savedID = UserDefaults.standard.string(forKey: "userID") {
            return savedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: "userID")
            return newID
        }
    }()
    
    init() {
        startRoomCleanupTimer()
    }
    
    @Published var gameState = "waiting"
    @Published var signal = ""
    @Published var isConnected = false
    @Published var sessionID: String = ""
    @Published var gameStatus: String = "active"
    @Published var autoMatchEnabled = true
    @Published var didCreateCurrentRoom = false
    @Published var showMatchFound: Bool = false
    @Published var isHost: Bool = false
    @Published var playerDisplayName: String = "Player"
    @Published var opponentDisplayName: String = "Opponent"
    
    var onOpponentMoveReceived: ((RPSMove) -> Void)?
    var onPhaseUpdate: ((String) -> Void)?
    var onWinnerResultReceived: ((String) -> Void)?
    var onSignalUpdate: ((String) -> Void)?
    var onOpponentForfeitDetected: (() -> Void)?
    var onVictoryResultReceived: ((String) -> Void)?
    
    func sendSignal(_ signal: String) {
        guard !sessionID.isEmpty else {
            print("❌ sendSignal skipped: sessionID is empty.")
            return
        }
        print("📡 Sending signal: \(signal)")
        db.collection("games").document(sessionID).updateData(["signal": signal])
    }
    
    func markWinnerDisplayed() {
        guard !sessionID.isEmpty else {
            print("❌ markWinnerDisplayed skipped: sessionID is empty.")
            return
        }
        
        let key = "winner_displayed_\(currentUserID)"
        let gameRef = db.collection("games").document(sessionID)
        
        gameRef.updateData([key: true]) { error in
            if let error = error {
                print("❌ Failed to mark winner displayed: \(error)")
                return
            }
            print("✅ Marked winner displayed for \(self.currentUserID)")
            
            guard !self.sessionID.isEmpty else {
                print("❌ Session ended before checking winner flags.")
                return
            }
            
            gameRef.getDocument { snapshot, error in
                guard !self.sessionID.isEmpty else {
                    print("❌ Session ended during getDocument.")
                    return
                }
                guard let data = snapshot?.data(), error == nil else { return }
                
                let allKeys = data.keys
                let hasTwo = allKeys.filter { $0.hasPrefix("winner_displayed_") }.count == 2
                
                if hasTwo {
                    print("✅ Both players marked winner displayed. Sending NEXT_ROUND.")
                    self.sendSignal("NEXT_ROUND")
                    
                    let batch = self.db.batch()
                    
                    for key in allKeys where key.hasPrefix("winner_displayed_") || key == "round_winner" {
                        batch.updateData([key: FieldValue.delete()], forDocument: gameRef)
                    }
                    
                    let movesRef = gameRef.collection("moves")
                    movesRef.getDocuments { snapshot, error in
                        if let docs = snapshot?.documents {
                            for doc in docs {
                                batch.deleteDocument(doc.reference)
                            }
                        }
                        
                        guard !self.sessionID.isEmpty else {
                            print("⚠️ Session ended before batch commit.")
                            return
                        }
                        
                        batch.commit { err in
                            if let err = err {
                                print("⚠️ Failed to clear flags or moves: \(err)")
                            } else {
                                print("🧹 Cleared winner_displayed, round_winner, and all moves.")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func clearSignalIfMatches(_ value: String) {
        guard signal == value else { return }
        db.collection("games").document(sessionID).updateData([
            "signal": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("⚠️ Failed to clear signal '\(value)': \(error.localizedDescription)")
            } else {
                print("✅ Cleared signal '\(value)' from Firestore.")
            }
        }
    }
    
    func checkIfOtherConfirmed(completion: @escaping (Bool) -> Void) {
        guard !sessionID.isEmpty else {
            completion(false)
            return
        }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            guard let data = snapshot?.data(), error == nil else {
                completion(false)
                return
            }
            
            let myKey = "inConfirmView_\(self.currentUserID)"
            let otherConfirmed = data.keys.contains { $0.hasPrefix("inConfirmView_") && $0 != myKey }
            completion(otherConfirmed)
        }
    }
    
    func requestStartMatch() {
        guard !sessionID.isEmpty else { return }
        let key = "requested_start_\(currentUserID)"
        db.collection("games").document(sessionID).updateData([key: true]) { error in
            if let error = error {
                print("❌ Failed to request start match: \(error)")
                return
            }
            
            self.db.collection("games").document(self.sessionID).getDocument { snapshot, error in
                guard let data = snapshot?.data(), error == nil else { return }
                let allKeys = data.keys
                let hasTwo = allKeys.filter { $0.hasPrefix("requested_start_") }.count == 2
                
                if hasTwo {
                    print("🚀 Both players requested match start. Sending START_MATCH")
                    self.generatePenaltyCountdown()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.sendSignal("START_MATCH")
                    }
                    
                    let batch = self.db.batch()
                    let ref = self.db.collection("games").document(self.sessionID)
                    for key in allKeys where key.hasPrefix("requested_start_") {
                        batch.updateData([key: FieldValue.delete()], forDocument: ref)
                    }
                    batch.commit()
                }
            }
        }
    }
    
    func fetchPenaltyCountdown(completion: @escaping (Int?) -> Void) {
        guard !sessionID.isEmpty else {
            completion(nil)
            return
        }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            if let data = snapshot?.data(), let value = data["penalty_countdown"] as? Int {
                print("⏱ Fetched penalty countdown: \(value)s")
                completion(value)
            } else {
                print("⚠️ Could not fetch penalty countdown.")
                completion(nil)
            }
        }
    }
    
    func joinPrivateRoom(code: String, completion: @escaping (Error?) -> Void) {
        print("🔐 Attempting to join private room with code: \(code)")
        let ref = db.collection("games").document(code)
        sessionID = code
        
        ref.getDocument { snapshot, error in
            if let error = error {
                print("❌ Firestore error while fetching private room: \(error)")
                completion(error)
                return
            }
            
            guard let doc = snapshot, doc.exists, var data = doc.data() else {
                print("❌ Room not found or error: \(error?.localizedDescription ?? "unknown")")
                completion(error)
                return
            }
            
            if data["player2"] == nil {
                let displayName = self.safeDisplayName()
                print("✅ Slot available. Joining room...")
                data["player2"] = self.currentUserID
                data["player2Name"] = displayName
                ref.setData(data, merge: true) { error in
                    if error != nil {
                        completion(error)
                        return
                    }
                    
                    print("✅ Joined room with code: \(code)")
                    self.isHost = false
                    self.listenForUpdates()
                    self.startHeartbeat()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        completion(nil)
                    }
                }
            } else {
                print("❌ Room already full (player2 already set).")
                completion(NSError(domain: "Room full", code: 400, userInfo: nil))
            }
        }
    }
    
    func sendMove(_ move: RPSMove) {
        guard !sessionID.isEmpty else {
            print("❌ sendMove skipped: sessionID is empty.")
            return
        }
        guard !hasSentMove else {
            print("⚠️ sendMove skipped: move already sent.")
            return
        }
        
        hasSentMove = true
        let now = Timestamp(date: Date())
        print("📤 Sending move \(move.rawValue) for user \(currentUserID) at \(now.dateValue())")
        
        let movesRef = db.collection("games").document(sessionID).collection("moves")
        movesRef.document(currentUserID).setData([
            "move": move.rawValue,
            "timestamp": now
        ]) { error in
            if let error = error {
                print("❌ Failed to send move: \(error)")
                return
            }
            
            guard !self.sessionID.isEmpty else {
                print("⚠️ Session ended before calculating winner.")
                return
            }
            
            print("✅ Move sent successfully. Checking if both moves are in...")
            self.calculateAndBroadcastWinnerIfReady()
        }
    }
    
    func fetchOpponentMove(completion: @escaping (RPSMove?) -> Void) {
        guard !sessionID.isEmpty else {
            completion(nil)
            return
        }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            
            let opponentKey = self.isHost ? "move_player2" : "move_player1"
            
            if let moveInt = data[opponentKey] as? Int,
               let move = RPSMove(rawValue: moveInt) {
                completion(move)
            } else {
                completion(nil)
            }
        }
    }
    
    func calculateAndBroadcastWinnerIfReady() {
        guard !sessionID.isEmpty else {
            print("❌ No session ID, can't calculate winner.")
            return
        }
        
        let movesRef = db.collection("games").document(sessionID).collection("moves")
        movesRef.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Failed to fetch moves: \(error)")
                return
            }
            
            guard let docs = snapshot?.documents, docs.count == 2 else {
                print("⏳ Waiting for both players to submit...")
                return
            }
            
            var moves: [String: Int] = [:]
            var timestamps: [String: Date] = [:]
            
            for doc in docs {
                let id = doc.documentID
                if let move = doc.data()["move"] as? Int {
                    moves[id] = move
                }
                if let ts = doc.data()["timestamp"] as? Timestamp {
                    timestamps[id] = ts.dateValue()
                }
            }
            
            guard moves.count == 2, timestamps.count == 2 else {
                print("⚠️ Could not extract both moves and timestamps.")
                return
            }
            
            let ids = Array(moves.keys)
            let (id1, id2) = (ids[0], ids[1])
            let (move1, move2) = (moves[id1]!, moves[id2]!)
            let (time1, time2) = (timestamps[id1]!, timestamps[id2]!)
            
            var winner: String
            
            if move1 == move2 {
                if abs(time1.timeIntervalSince(time2)) < Double.ulpOfOne {
                    winner = "tie"
                    print("🤝 True tie: same move, tapped at nearly the same time.")
                } else {
                    winner = time1 < time2 ? id1 : id2
                    print("⏱ Tie broken by speed. Faster tap wins: \(winner)")
                }
            } else if (move1 == 3 && move2 == 2) || (move1 == 2 && move2 == 1) || (move1 == 1 && move2 == 3) {
                winner = id1
            } else {
                winner = id2
            }
            
            print("🏆 Final round winner determined: \(winner)")
            
            guard !self.sessionID.isEmpty else {
                print("⚠️ Session ended before writing winner to Firestore.")
                return
            }
            
            let gameRef = self.db.collection("games").document(self.sessionID)
            gameRef.updateData([
                "round_winner": winner,
                "phase": "ROUND_OVER"
            ]) { err in
                if let err = err {
                    print("❌ Failed to write round_winner and phase: \(err)")
                } else {
                    print("✅ round_winner = \(winner), phase = ROUND_OVER")
                }
            }
        }
    }
    
    func reset() {
        print("🧹 Resetting FirestoreManager (clearing sessionID and state)")
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        listener?.remove()
        listener = nil
        
        isConnected = false
        signal = ""
        gameStatus = "active"
        didCreateCurrentRoom = false
        sessionID = ""
    }
    
    func updateGamePhase(_ newPhase: String) {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).updateData(["phase": newPhase])
    }
    
    func forceDisconnect() {
        print("⚠️ Force disconnecting from session: \(sessionID)")
        stopListening()
        isConnected = false
        autoMatchEnabled = false
        signal = ""
    }
    
    func listenForOpponentMove() {
        guard !sessionID.isEmpty else {
            print("❌ listenForOpponentMove: sessionID is empty")
            return
        }
        
        db.collection("games").document(sessionID).collection("moves")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                for document in documents {
                    let docID = document.documentID
                    if docID != self.currentUserID, let rawMove = document.data()["move"] as? Int,
                       let move = RPSMove(rawValue: rawMove) {
                        print("📥 Opponent move received: \(move) from \(docID)")
                        DispatchQueue.main.async {
                            self.onOpponentMoveReceived?(move)
                        }
                    }
                }
            }
        
        print("👂 Now listening for opponent moves in room \(sessionID)")
    }
    
    func listenForUpdates() {
        guard !sessionID.isEmpty else { return }
        
        var didTriggerConnection = false
        
        listener = db.collection("games").document(sessionID).addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(), error == nil else {
                print("❌ Failed to fetch game document or snapshot error.")
                return
            }
            
            if let name1 = data["player1Name"] as? String {
                print("👤 Player 1: \(name1)")
            }
            if let name2 = data["player2Name"] as? String {
                print("👤 Player 2: \(name2)")
            }
            
            if let player1ID = data["player1"] as? String,
               let _ = data["player2"] as? String,
               let name1 = data["player1Name"] as? String,
               let name2 = data["player2Name"] as? String {
                
                if self.currentUserID == player1ID {
                    DispatchQueue.main.async {
                        self.playerDisplayName = name1
                        self.opponentDisplayName = name2
                    }
                } else {
                    DispatchQueue.main.async {
                        self.playerDisplayName = name2
                        self.opponentDisplayName = name1
                    }
                }
            }
            
            let player1 = data["player1"] as? String
            let player2 = data["player2"] as? String
            if player1 != nil && player2 != nil && !didTriggerConnection {
                didTriggerConnection = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("📡 FirestoreManager: Both players joined. isConnected = true")
                    self.isConnected = true
                }
            }
            
            if let status = data["gameStatus"] as? String {
                DispatchQueue.main.async {
                    self.gameStatus = status
                }
                if status == "closed" || status == "forfeited" {
                    print("⚠️ Game is \(status). Listener stopping logic if needed.")
                    return
                }
            }
            
            if let newSignal = data["signal"] as? String {
                DispatchQueue.main.async {
                    self.signal = newSignal
                    self.onSignalUpdate?(newSignal)
                    
                    switch newSignal {
                    case "START_MATCH":
                        self.onPhaseUpdate?("START_MATCH")
                    case "OPPONENT_DISCONNECTED":
                        self.onPhaseUpdate?("OPPONENT_DISCONNECTED")
                    default:
                        break
                    }
                }
            }
            
            if let winner = data["round_winner"] as? String {
                let result: String
                if winner == self.currentUserID {
                    result = "player"
                } else if winner == "tie" {
                    result = "tie"
                } else {
                    result = "opponent"
                }
                
                print("🏆 Firestore detected round_winner = \(winner), mapped to result = \(result)")
                DispatchQueue.main.async {
                    self.onWinnerResultReceived?(result)
                }
            }
            
            let opponentKey = data["player1"] as? String == self.currentUserID ? "player2" : "player1"
            guard let opponentID = data[opponentKey] as? String else {
                print("❓ No opponent yet.")
                return
            }
            
            let now = Date()
            let myHeartbeat = data["heartbeat_\(self.currentUserID)"] as? Timestamp
            let opponentHeartbeat = data["heartbeat_\(opponentID)"] as? Timestamp
            
            let myElapsed = myHeartbeat.map { now.timeIntervalSince($0.dateValue()) } ?? .infinity
            let opponentElapsed = opponentHeartbeat.map { now.timeIntervalSince($0.dateValue()) } ?? .infinity
            
            let myDisplay = myElapsed.isFinite ? "\(Int(myElapsed))s" : "∞"
            let opponentDisplay = opponentElapsed.isFinite ? "\(Int(opponentElapsed))s" : "∞"
            
            print("💓 Heartbeat check: me = \(myDisplay), opponent = \(opponentDisplay)")
            
            if opponentElapsed > 10 {
                print("❌ Opponent heartbeat timeout detected. Confirming in 2s...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.db.collection("games").document(self.sessionID).getDocument { snapshot, error in
                        guard let data = snapshot?.data(), error == nil else { return }
                        
                        let now = Date()
                        let newOp = data["heartbeat_\(opponentID)"] as? Timestamp
                        let newOpElapsed = newOp.map { now.timeIntervalSince($0.dateValue()) } ?? .infinity
                        
                        if newOpElapsed > 10 {
                            print("☠️ Confirmed: opponent is disconnected. Sending signal to end game.")
                            self.sendSignal("OPPONENT_DISCONNECTED")
                        } else {
                            print("✅ False alarm. Opponent heartbeat recovered.")
                        }
                    }
                }
            }
        }
    }
    
    func incrementRoundNumber() {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).updateData([
            "round_number": FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                print("❌ Failed to increment round number: \(error)")
            } else {
                print("🔁 Round number incremented by 1")
            }
        }
    }
    
    func fetchRoundNumber(completion: @escaping (Int?) -> Void) {
        guard !sessionID.isEmpty else {
            completion(nil)
            return
        }
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            if let data = snapshot?.data(), let round = data["round_number"] as? Int {
                completion(round)
            } else {
                completion(nil)
            }
        }
    }
    
    func updateRoundNumber(_ round: Int) {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).updateData([
            "round_number": round
        ]) { error in
            if let error = error {
                print("❌ Failed to update round number: \(error)")
            } else {
                print("✅ Round number updated to \(round)")
            }
        }
    }
    
    func clearEarlyTapSignal() {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).updateData([
            "signal": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("⚠️ Failed to clear early tap signal: \(error)")
            } else {
                print("✅ Cleared early tap signal from Firestore.")
            }
        }
    }
    
    func recordDuelStartTime() {
        guard !sessionID.isEmpty else { return }
        let now = Timestamp(date: Date())
        db.collection("games").document(sessionID).updateData([
            "duel_start_time": now
        ]) { error in
            if let error = error {
                print("❌ Failed to record duel start time: \(error)")
            } else {
                print("✅ Duel start time recorded.")
            }
        }
    }
    
    func clearSignalIfStartsWith(_ prefix: String) {
        guard !sessionID.isEmpty else { return }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            guard let data = snapshot?.data(), error == nil else { return }
            if let signal = data["signal"] as? String, signal.starts(with: prefix) {
                self.db.collection("games").document(self.sessionID).updateData([
                    "signal": FieldValue.delete()
                ]) { error in
                    if let error = error {
                        print("⚠️ Failed to clear signal starting with '\(prefix)': \(error.localizedDescription)")
                    } else {
                        print("✅ Cleared signal starting with '\(prefix)' from Firestore.")
                    }
                }
            }
        }
    }
    
    func fetchDuelStartTime(completion: @escaping (Timestamp?) -> Void) {
        guard !sessionID.isEmpty else {
            completion(nil)
            return
        }
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let timestamp = data["duel_start_time"] as? Timestamp {
                completion(timestamp)
            } else {
                print("⚠️ Could not fetch duel_start_time.")
                completion(nil)
            }
        }
    }
    
    func cleanupMyRooms() {
        print("🧹 Cleaning up my own unused rooms...")
        
        db.collection("games")
            .whereField("creatorID", isEqualTo: currentUserID)
            .whereField("gameStatus", isEqualTo: "active")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Failed to fetch rooms for cleanup: \(error)")
                    return
                }
                
                for doc in snapshot?.documents ?? [] {
                    let data = doc.data()
                    let state = data["state"] as? String ?? "unknown"
                    let isPrivate = data["private"] as? Bool ?? false
                    let id = doc.documentID
                    
                    _ = data["player1"] as? String
                    let player2 = data["player2"] as? String
                    
                    let isWaiting = state == "waiting"
                    let isAlone = player2 == nil
                    
                    if isWaiting && isAlone {
                        print("🗑 Deleting unused \(isPrivate ? "private" : "public") room: \(id)")
                        self.db.collection("games").document(id).delete()
                    } else {
                        print("❎ Skipping room: \(id) — state: \(state), player2: \(String(describing: player2))")
                    }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    func clearStartMatchSignal() {
        guard !sessionID.isEmpty else { return }
        print("🧹 Clearing START_MATCH signal in Firestore.")
        db.collection("games").document(sessionID).updateData(["signal": ""]) { error in
            if let error = error {
                print("❌ Failed to clear START_MATCH signal: \(error)")
            } else {
                print("✅ START_MATCH signal cleared.")
            }
        }
    }
    
    func generatePenaltyCountdown() {
        guard !sessionID.isEmpty else {
            print("❌ Cannot generate countdown — sessionID is empty.")
            return
        }
        
        let countdown = Int.random(in: 0...3)
        print("⏱ Generated penalty countdown: \(countdown)s")
        
        db.collection("games").document(sessionID).updateData([
            "penalty_countdown": countdown
        ]) { error in
            if let error = error {
                print("❌ Failed to store penalty countdown: \(error)")
            } else {
                print("✅ Penalty countdown stored in Firestore.")
            }
        }
    }
    
    func tryStartMatchIfBothConfirmed() {
        guard !sessionID.isEmpty else {
            print("❌ Cannot check confirmations: sessionID is empty.")
            return
        }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            guard let data = snapshot?.data(), error == nil else {
                print("❌ Failed to fetch game data for confirmation check: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            let confirmedKeys = data.keys.filter { $0.hasPrefix("confirmed_") }
            print("📋 Confirmed keys found: \(confirmedKeys)")
            
            if confirmedKeys.count == 2 {
                print("✅ Both players confirmed. Sending CONFIRMED signal to transition to ReadyView.")
                self.sendSignal("CONFIRMED")
            } else {
                print("⏳ Waiting for both players to confirm... (\(confirmedKeys.count)/2)")
            }
        }
    }
    
    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        
        guard !sessionID.isEmpty else { return }
        let key = "heartbeat_\(currentUserID)"
        
        db.collection("games").document(sessionID).updateData([
            key: FieldValue.serverTimestamp()
        ]) {
            if let error = $0 {
                print("⚠️ Failed to send initial heartbeat: \(error)")
            } else {
                print("💓 Initial heartbeat sent for \(self.currentUserID)")
            }
        }
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard !self.sessionID.isEmpty else { return }
            let key = "heartbeat_\(self.currentUserID)"
            
            self.db.collection("games").document(self.sessionID).updateData([
                key: FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("⚠️ Failed to send heartbeat: \(error)")
                } else {
                    print("💓 Heartbeat updated for \(self.currentUserID) at \(Date())")
                }
            }
        }
    }
    
    func closeGameRoom() {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).delete()
    }
    
    func fetchLatestSignal(completion: @escaping (String?) -> Void) {
        guard !sessionID.isEmpty else {
            completion(nil)
            return
        }
        
        db.collection("games").document(sessionID).getDocument { snapshot, error in
            if let signal = snapshot?.data()?["signal"] as? String {
                print("📦 Fetched latest signal manually: \(signal)")
                completion(signal)
            } else {
                completion(nil)
            }
        }
    }
    
    func confirmPlayerReady() {
        guard !sessionID.isEmpty else { return }
        let key = "confirmed_\(currentUserID)"
        db.collection("games").document(sessionID).updateData([key: true])
    }
    
    func deleteRoom(code: String) {
        db.collection("games").document(code).delete()
    }
    
    func connect() {
        guard autoMatchEnabled else {
            print("⚠️ Auto match is disabled.")
            return
        }
        
        print("🔍 Attempting to find an open public game room...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.db.collection("games")
                .whereField("state", isEqualTo: "waiting")
                .whereField("private", isEqualTo: false)
                .whereField("gameStatus", isEqualTo: "active")
                .order(by: "createdAt", descending: false)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("❌ Firestore error while querying public rooms: \(error)")
                        return
                    }
                    
                    let now = Date()
                    for doc in snapshot?.documents ?? [] {
                        let data = doc.data()
                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        let isTooOld = createdAt < now.addingTimeInterval(-600)
                        
                        let player1 = data["player1"] as? String ?? ""
                        let player2 = data["player2"] as? String
                        
                        if player1 == self.currentUserID {
                            print("⛔ Skipping own room: \(doc.documentID)")
                            continue
                        }
                        
                        let hb1Key = "heartbeat_\(player1)"
                        let hb1 = (data[hb1Key] as? Timestamp)?.dateValue() ?? Date.distantPast
                        
                        let hb2Key = "heartbeat_\(player2 ?? "")"
                        let hb2 = player2 != nil ? (data[hb2Key] as? Timestamp)?.dateValue() ?? Date.distantPast : nil
                        
                        let hb1Delta = now.timeIntervalSince(hb1)
                        let hb2Delta = hb2 != nil ? now.timeIntervalSince(hb2!) : 0
                        
                        let isStale = hb1Delta > 10 || hb2Delta > 10
                        
                        if isTooOld || isStale {
                            print("🛑 Skipping stale room: \(doc.documentID)")
                            continue
                        }
                        
                        if data["player2"] == nil {
                            let displayName = self.safeDisplayName()
                            print("✅ Found an existing public room: \(doc.documentID)")
                            self.sessionID = doc.documentID
                            self.didCreateCurrentRoom = false
                            self.isHost = false
                            
                            self.db.collection("games").document(doc.documentID).updateData([
                                "player2": self.currentUserID,
                                "player2Name": displayName,
                                "state": "connected"
                            ]) { error in
                                if let error = error {
                                    print("❌ Failed to join public room: \(error)")
                                    return
                                }
                                
                                print("✅ Joined as player2 in public room.")
                                DispatchQueue.main.async {
                                    self.isConnected = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    self.listenForUpdates()
                                    self.startHeartbeat()
                                }
                            }
                            
                            return
                        }
                    }
                    
                    let newID = UUID().uuidString
                    let displayName = self.safeDisplayName()
                    print("📭 Creating new public room: \(newID)")
                    self.sessionID = newID
                    self.didCreateCurrentRoom = true
                    self.isHost = true
                    
                    self.db.collection("games").document(newID).setData([
                        "state": "waiting",
                        "signal": "",
                        "gameStatus": "active",
                        "private": false,
                        "creatorID": self.currentUserID,
                        "player1": self.currentUserID,
                        "player1Name": displayName,
                        "round_number": 1,
                        "createdAt": FieldValue.serverTimestamp()
                    ]) { err in
                        if let err = err {
                            print("❌ Failed to create new room: \(err)")
                        } else {
                            print("✅ Created new public room: \(newID)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.listenForUpdates()
                                self.startHeartbeat()
                            }
                        }
                    }
                }
        }
    }
    
    func createPrivateRoom() -> String {
        let code = generateRoomCode()
        sessionID = code
        didCreateCurrentRoom = true
        self.isHost = true
        
        let displayName = self.safeDisplayName()
        print("🔐 Creating private room with code: \(code)")
        
        db.collection("games").document(code).setData([
            "state": "waiting",
            "signal": "",
            "gameStatus": "active",
            "private": true,
            "creatorID": currentUserID,
            "player1": currentUserID,
            "player1Name": displayName,
            "round_number": 1,
            "createdAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ Failed to create private room: \(error)")
            } else {
                print("✅ Private room created with code: \(code)")
                self.listenForUpdates()
                self.startHeartbeat()
            }
        }
        
        return code
    }
    
    func forfeitMatch() {
        guard !sessionID.isEmpty else {
            print("❌ Cannot forfeit: sessionID is empty.")
            return
        }
        
        let signal = "FORFEIT_BY_\(currentUserID)"
        print("⚠️ Sending forfeit signal: \(signal)")
        sendSignal(signal)
    }
    
    func startRoomCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            self.cleanupStaleRooms()
        }
    }
    
    func cleanupStaleRooms() {
        print("🧹 Running scheduled stale room cleanup...")
        
        db.collection("games")
            .whereField("gameStatus", isEqualTo: "active")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error during stale room cleanup: \(error)")
                    return
                }
                
                let now = Date()
                
                for doc in snapshot?.documents ?? [] {
                    let data = doc.data()
                    let state = data["state"] as? String ?? ""
                    let privateRoom = data["private"] as? Bool ?? false
                    let createdAt = data["createdAt"] as? Timestamp ?? Timestamp()
                    let isTooOld = createdAt.dateValue() < now.addingTimeInterval(-600)
                    
                    if !privateRoom && isTooOld && (state == "waiting" || state == "connected") {
                        print("🗑 Scheduled cleanup: deleting stale room \(doc.documentID)")
                        self.db.collection("games").document(doc.documentID).delete()
                    }
                }
            }
    }
    
    private func generateRoomCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
    
    func sendVictorySignal() {
        guard !sessionID.isEmpty else {
            print("❌ Cannot send VICTORY signal — sessionID is empty.")
            return
        }
        
        print("📣 Sending VICTORY signal to Firestore.")
        sendSignal("VICTORY")
    }
    
    func markEnteredConfirmView() {
        guard !sessionID.isEmpty else { return }
        let key = "inConfirmView_\(currentUserID)"
        db.collection("games").document(sessionID).updateData([key: true])
    }
    
    func markRejection(reason: String) {
        guard !sessionID.isEmpty else { return }
        db.collection("games").document(sessionID).updateData([
            "rejection_reason": reason,
            "gameStatus": "closed"
        ])
    }
    
    private func safeDisplayName() -> String {
        let name = GKLocalPlayer.local.displayName
        return GKLocalPlayer.local.isAuthenticated && !name.isEmpty ? name : "Player"
    }
}
