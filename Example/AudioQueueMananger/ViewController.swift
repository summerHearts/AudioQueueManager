//
//  ViewController.swift
//  SwiftProtocolExtension
//
//  Created by mars.yao on 2023/11/20.
//

import UIKit
import AudioQueueMananger

class ViewController: UIViewController {
    
    @IBAction func playQueueAudioAction(_ sender: Any) {
        
        audioQueueManager.removeAllAudio()
        
        let item1 = AudioQueueItem(file: "1", priority: .normal)
        audioQueueManager.addToQueue(item1)
        
        let item2 = AudioQueueItem(file: "2", priority: .normal)
        audioQueueManager.addToQueue(item2)
        
        let item3 = AudioQueueItem(file: "3", priority: .normal)
        audioQueueManager.addToQueue(item3)
        
        let item4 = AudioQueueItem(file: "4", priority: .normal)
        audioQueueManager.addToQueue(item4)
        
        let item5 = AudioQueueItem(file: "6", priority: .normal)
        audioQueueManager.addToQueue(item5)
    }
    
    let audioQueueManager = AudioQueueManager()


    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // For a higher priority audio
        let item3 = AudioQueueItem(file: "5", priority: .high)
        audioQueueManager.interruptForHigherPriority(item3)
    }

}

