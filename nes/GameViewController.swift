//
//  GameViewController.swift
//  nes
//
//  Created by mike on 8/3/25.
//

import Cocoa
import SpriteKit

class GameViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create the scene
        let scene = GameScene()
        scene.size = CGSize(width: 512, height: 480)
        scene.scaleMode = .aspectFit
        
        // Present the scene
        if let skView = self.view as? SKView {
            skView.presentScene(scene)
            skView.ignoresSiblingOrder = true
            skView.showsFPS = true
            skView.showsNodeCount = true
        }
    }
}
