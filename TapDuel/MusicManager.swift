//
//  MusicManager.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/30/25.
//

import AVFAudio

class MusicManager {
    static let shared = MusicManager()
    
    var player: AVAudioPlayer?
    var currentTrackName: String?
    var shouldResumeAfterInterruption = false
    var isMuted = false
    var currentVolume: Float = 0.5

    func playLobbyMusic() {
        playMusic(named: "Lobby")
    }

    func playGameMusic() {
        playMusic(named: "Game")
    }

    private func playMusic(named name: String) {
        if currentTrackName == name, player?.isPlaying == true {
            print("⏭️ \(name).wav is already playing, skipping.")
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("❌ Could not find \(name).wav in bundle.")
            return
        }

        print("🎶 Loading \(name).wav...")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = isMuted ? 0 : currentVolume
            player?.prepareToPlay()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.player?.play()
                self.currentTrackName = name
                print("✅ \(name).wav is now playing.")
            }

            shouldResumeAfterInterruption = true
        } catch {
            print("❌ Error loading \(name).wav: \(error)")
        }
    }

    func stopMusic() {
        guard player?.isPlaying == true else {
            print("⛔️ No music to stop.")
            return
        }

        player?.stop()
        shouldResumeAfterInterruption = false
        print("🛑 Music stopped.")
        currentTrackName = nil
    }

    func resumeIfNeeded() {
        if shouldResumeAfterInterruption, player?.isPlaying == false {
            player?.play()
            print("🔁 Resumed music after interruption.")
        }
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        if !isMuted {
            player?.volume = volume
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.volume = muted ? 0 : currentVolume
    }
}


