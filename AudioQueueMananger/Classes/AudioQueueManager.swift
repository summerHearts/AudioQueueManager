//
//  AudioQueueManager.swift
//  SwiftProtocolExtension
//
//  Created by mars.yao on 2023/11/21.
//

import Foundation
import AVFAudio

public enum AudioPriority: Int {
    case normal
    case high
}

public struct AudioQueueItem {
    public let file: String
    public let priority: AudioPriority
    public init(file: String, priority: AudioPriority) {
        self.file = file
        self.priority = priority
    }
}

public class AudioQueueManager: NSObject {
    
    public var audioQueue: [AudioQueueItem] = []
    public var audioPlayer: AVAudioPlayer?
    public var isPlaying: Bool = false
    
    public var volumeCheckTimer: Timer?
    
    public let queueDispatchQueue = DispatchQueue(label: "audioQueueManager")
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterruptionNotification), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        setupVolumeCheckTimer()
    }
    
    public func addToQueue(_ item: AudioQueueItem) {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.append(item)
            self?.audioQueue.sort { $0.priority == .high && $1.priority == .normal }
            if !(self?.isPlaying ?? false) {
                self?.tryPlayNext()
            }
        }
    }
    
    public func removeAllAudio() {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.removeAll()
        }
    }
    
    public func tryPlayNext() {
        queueDispatchQueue.async { [weak self] in
            guard let nextItem = self?.audioQueue.first else {
                self?.resetAudioStatus()
                self?.isPlaying = false
                return
            }
            self?.isPlaying = true
            self?.playAudio(file: nextItem.file) {
            
            }
        }
    }
    
    public func playAudio(file: String, completion: @escaping () -> Void) {
        guard let soundURL = Bundle.main.url(forResource: file, withExtension: "mp3") else {
            print("Audio file not found")
            completion()
            return
        }
        
        queueDispatchQueue.async { [weak self] in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, options: [AVAudioSession.CategoryOptions.defaultToSpeaker])
                try audioSession.setActive(true, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
                
                self?.audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                self?.audioPlayer?.delegate = self
                self?.audioPlayer?.numberOfLoops = 0
                self?.audioPlayer?.volume = 1
                self?.audioPlayer?.play()
                
                
                guard let duration = self?.audioPlayer?.duration else {
                    completion()
                    return
                }
                
                let when = DispatchTime.now() + duration + 0.5
                DispatchQueue.main.asyncAfter(deadline: when) {
                    completion()
                }
                
            } catch {
                print("Error playing audio: \(error.localizedDescription)")
                completion()
            }
        }
    }
    
    public func interruptForHigherPriority(_ item: AudioQueueItem) {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.insert(item, at: 0)
            self?.stopCurrentAndPlayNext()
        }
    }
    
    public func stopCurrentAudio() {
        self.audioPlayer?.stop()
    }
    
    public func stopCurrentAndPlayNext() {
        queueDispatchQueue.async { [weak self] in
            self?.audioPlayer?.stop()
            self?.isPlaying = false
            self?.tryPlayNext()
        }
    }
    
    public func setupVolumeCheckTimer() {
        if volumeCheckTimer == nil {
            volumeCheckTimer = Timer.scheduledTimer(timeInterval: 1.0, 
                                                    target: self,
                                                    selector: #selector(checkVolumeLevel),
                                                    userInfo: nil,
                                                    repeats: true)
        }
    }
    
    @objc func checkVolumeLevel() {
        let currentVolume = AVAudioSession.sharedInstance().outputVolume
        print("Current system volume: \(currentVolume)")
    }
    
    @objc
    private func audioInterruptionNotification(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else {
            return
        }
        
        switch interruptionType {
        case .began:
            // 中断开始，停止播放
            stopCurrentAudio()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // 中断结束，恢复播放
                    self.tryPlayNext()
                }
            }
        @unknown default:
            print("")
        }
    }
    
    public func resetAudioStatus() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
        }  catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }
    
    public func destoryTimer() {
        self.volumeCheckTimer?.invalidate()
        self.volumeCheckTimer = nil
    }
}

extension AudioQueueManager: AVAudioPlayerDelegate {
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.audioQueue.isEmpty {
            return
        }
        self.audioQueue.removeFirst()
        self.tryPlayNext()
    }
}
