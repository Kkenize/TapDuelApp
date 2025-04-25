//
//  GameConfirmViewBackground.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/17/25.
//

import Foundation
import SpriteKit

class GameConfirmViewBackground: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .white
        drawNotebookLines()
    }

    private func drawNotebookLines() {
        let spacing: CGFloat = 40
        let lineColor = UIColor.systemBlue.withAlphaComponent(0.15)
        let marginColor = UIColor.red.withAlphaComponent(0.2)
        
        for y in stride(from: 0.0, through: size.height, by: spacing) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))

            let line = SKShapeNode(path: path)
            line.strokeColor = lineColor
            line.lineWidth = 1
            addChild(line)
        }
        
        let marginX: CGFloat = 60
        let marginPath = CGMutablePath()
        marginPath.move(to: CGPoint(x: marginX, y: 0))
        marginPath.addLine(to: CGPoint(x: marginX, y: size.height))

        let marginLine = SKShapeNode(path: marginPath)
        marginLine.strokeColor = marginColor
        marginLine.lineWidth = 1.5
        addChild(marginLine)
    }
}
