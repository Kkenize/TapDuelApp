//
//  FingerTapViewRepresentable.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 3/31/25.
//

import SwiftUI

struct FingerTapViewRepresentable: UIViewRepresentable {
    var onFirstValidTap: (Int) -> Void

    func makeUIView(context: Context) -> FingerTapView {
        let view = FingerTapView()
        view.onFirstValidTap = onFirstValidTap
        context.coordinator.fingerTapView = view
        return view
    }

    func updateUIView(_ uiView: FingerTapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var fingerTapView: FingerTapView?

        func reset() {
            fingerTapView?.resetForNewRound()
        }
    }

    class FingerTapView: UIView {
        var onFirstValidTap: ((Int) -> Void)?
        private var hasTappedThisRound = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard !hasTappedThisRound else { return }

            let touchCount = event?.allTouches?.count ?? 0
            if (1...3).contains(touchCount) {
                hasTappedThisRound = true
                onFirstValidTap?(touchCount)
            }
        }

        func resetForNewRound() {
            hasTappedThisRound = false
        }
    }
}

