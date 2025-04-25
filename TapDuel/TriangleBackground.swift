//
//  TriangleBackground.swift
//  TapDuel
//
//  Created by Zhejun Zhang on 4/17/25.
//

import Foundation
import SpriteKit

class TriangleBackground: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .white
        drawNotebookLines()
        drawHollowTriangle()
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
    
    private func drawHollowTriangle() {
            let path = CGMutablePath()
            let width = size.width
            let height = size.height
            let triangleSize: CGFloat = 200

            let center = CGPoint(x: width / 2, y: height / 2)
            let top = CGPoint(x: center.x, y: center.y + triangleSize / 2)
            let left = CGPoint(x: center.x - triangleSize / 2, y: center.y - triangleSize / 2)
            let right = CGPoint(x: center.x + triangleSize / 2, y: center.y - triangleSize / 2)

            path.move(to: top)
            path.addLine(to: right)
            path.addLine(to: left)
            path.addLine(to: top)

            let shape = SKShapeNode(path: path)
            shape.strokeColor = .green
            shape.lineWidth = 10
            shape.fillColor = .clear
            addChild(shape)
        }
}
