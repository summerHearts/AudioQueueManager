# AudioQueueMananger

[![CI Status](https://img.shields.io/travis/summerhearts@163.com/AudioQueueMananger.svg?style=flat)](https://travis-ci.org/summerhearts@163.com/AudioQueueMananger)
[![Version](https://img.shields.io/cocoapods/v/AudioQueueMananger.svg?style=flat)](https://cocoapods.org/pods/AudioQueueMananger)
[![License](https://img.shields.io/cocoapods/l/AudioQueueMananger.svg?style=flat)](https://cocoapods.org/pods/AudioQueueMananger)
[![Platform](https://img.shields.io/cocoapods/p/AudioQueueMananger.svg?style=flat)](https://cocoapods.org/pods/AudioQueueMananger)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

AudioQueueMananger is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'AudioQueueMananger'
```
iOS 语音播放以及何检测其他应用或组件正在占用音频会话或音频输出设备等情况处理的实现 

## 队列实现的播报语音方案
**AVAudioPlayer**主要用于播放预先录制好的音频文件，不适用于语音合成和播报。如果你有多个音频文件需要按优先级播放，并需要队列管理和错误处理，且需要实现线程安全你可以使用以下基于**AVAudioPlayer**的代码框架来实现：
### 管理类封装
```swift
import Foundation
import AVFoundation

enum AudioPriority: Int {
    case normal
    case high
}

struct AudioQueueItem {
    let file: String
    let priority: AudioPriority
}

class AudioQueueManager: NSObject {
    
    var audioQueue: [AudioQueueItem] = []
    var audioPlayer: AVAudioPlayer?
    var isPlaying: Bool = false
    
    var volumeCheckTimer: Timer?
    
    private let queueDispatchQueue = DispatchQueue(label: "audioQueueManager")
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterruptionNotification), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        setupVolumeCheckTimer()
    }
    
    func addToQueue(_ item: AudioQueueItem) {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.append(item)
            self?.audioQueue.sort { $0.priority == .high && $1.priority == .normal }
            if !(self?.isPlaying ?? false) {
                self?.tryPlayNext()
            }
        }
    }
    
    func removeAllAudio() {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.removeAll()
        }
    }
    
    func tryPlayNext() {
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
    
    func playAudio(file: String, completion: @escaping () -> Void) {
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
    
    func interruptForHigherPriority(_ item: AudioQueueItem) {
        queueDispatchQueue.async { [weak self] in
            self?.audioQueue.insert(item, at: 0)
            self?.stopCurrentAndPlayNext()
        }
    }
    
    func stopCurrentAudio() {
        self.audioPlayer?.stop()
    }
    
    private func stopCurrentAndPlayNext() {
        queueDispatchQueue.async { [weak self] in
            self?.audioPlayer?.stop()
            self?.isPlaying = false
            self?.tryPlayNext()
        }
    }
    
    func setupVolumeCheckTimer() {
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
    
    func resetAudioStatus() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
        }  catch {
            print("Error playing audio: \(error.localizedDescription)")
        }
    }

   func destoryTimer() {
        self.volumeCheckTimer?.invalidate()
        self.volumeCheckTimer = nil
    }
}

extension AudioQueueManager: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.audioQueue.isEmpty {
            return
        }
        self.audioQueue.removeFirst()
        self.tryPlayNext()
    }
}

```
这个示例代码中的 **AudioQueueManager** 类基于 **AVAudioPlayer** 实现了音频播放的队列管理和优先级控制。它通过 **audioQueue** 存储待播放的音频文件和优先级，按照优先级进行播放。播放完成后，会自动播放下一个音频文件。
### 使用方式
```swift
import UIKit
import AVFAudio

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

```
### 优化播报了一段音频逻辑
 比如如果正在播放的音频已经播放了80%，那么即使被更高优任务抢占，依旧将其移出播报队列，不再播报。
在 AVAudioPlayer 类中，currentTime 和 deviceCurrentTime 是两个关于时间的属性，但它们各自有不同的用途和含义：

1. **currentTime**
currentTime 属性表示音频播放器当前播放的位置。
- 它的值是一个以秒为单位的浮点数，表示从音频文件开始的时间。
- 你可以读取 currentTime 来获取当前播放位置，也可以设置这个值来改变播放位置。

例如，如果你想跳到音频文件的第10秒开始播放：
```swift
audioPlayer.currentTime = 10.0

```
这个属性在实现音频播放器的进度条或者跳转功能时非常有用。

2. **deviceCurrentTime**
deviceCurrentTime 属性返回音频设备的当前时间。
- 这个时间是音频设备系统时钟的一个值，用于安排音频播放或者录音的开始。
- 它不反映音频文件的播放位置，而是用于同步音频的时间戳。

例如，如果你想在特定的设备时间开始播放音频：
```swift
let time: TimeInterval = audioPlayer.deviceCurrentTime + 0.5
audioPlayer.play(atTime: time)
```
这个属性通常用于需要高精度时间控制的场景，比如在特定时间点同步音频播放。

- 使用 currentTime 来获取或设置音频文件中的当前播放位置。
- 使用 deviceCurrentTime 来获得音频设备的系统时间，适用于需要精确时间控制的场合。
## AVAudioSession参数详解
### AVAudioSessionCategory 
AVAudioSessionCategory在 iOS 中用于配置应用程序的音频会话，这决定了您的应用音频如何与设备上的其他音频交互。它是 AVFoundation 框架的一部分。每个类别都有关于如何播放和录制音频的特定行为和规则。以下是您可以使用的主要类别：

1. **AVAudioSession.Category.playback**
用于播放对应用程序成功使用至关重要的录制音乐或其他声音。
当静音模式开关设置为静音或屏幕锁定时，音频继续播放。
示例用例：音乐播放器应用。
2. **AVAudioSession.Category.record**
用于录制音频。
静音播放音频。
示例用例：语音录制应用。
3. **AVAudioSession.Category.playAndRecord**
用于需要同时播放和录制的应用程序。
允许同时进行录音（输入）和播放（输出）。
示例用例：语音IP（VoIP）应用。
4. **AVAudioSession.Category.ambient**
用于播放对应用程序目的不是中心的音频。
音频被铃声/静音开关和屏幕锁定时静音。
允许其他背景音频继续播放（可混合）。
示例用例：带背景音乐的游戏应用。
5. **AVAudioSession.Category.soloAmbient**
默认类别。
类似于环境类别，但当您的应用音频开始时会停止其他背景音频。
音频被铃声/静音开关和屏幕锁定时静音。
示例用例：偶尔带有音效的休闲应用。
6. **AVAudioSession.Category.multiRoute**
用于同时将不同的音频数据流路由到不同的输出设备。
示例用例：DJ 应用，将一个音频流发送到扬声器系统，将不同的流发送到耳机。
设置音频会话类别


在 Swift 中设置音频会话类别：
```swift
do {
    try AVAudioSession.sharedInstance().setCategory(.playback)
    try AVAudioSession.sharedInstance().setActive(true)
} catch {
    print("设置音频会话类别失败。错误：(error)")
}
```
### AVAudioSessionCategoryOption 
 AVAudioSessionCategoryOption是 iOS 中 AVAudioSession 的一个配置选项，它提供了更细致的控制，用于在特定的 AVAudioSessionCategory 中定制音频行为。以下是一些常见的 AVAudioSessionCategoryOption 选项：

1. **AVAudioSession.CategoryOptions.mixWithOthers**
允许你的应用在播放音频时与其他应用混合音频。
常用于 .ambient 或 .playback 类别。
示例用途：允许用户在使用你的应用时同时听其他音乐应用的音乐。
2. **AVAudioSession.CategoryOptions.duckOthers**
当你的应用播放音频时，降低其他应用的音频音量。
常用于提供短暂音频提示的情况，如导航应用在播放指示时降低背景音乐音量。
示例用途：GPS 导航应用在提供方向指示时暂时降低其他音乐应用的音量。
3. **AVAudioSession.CategoryOptions.allowBluetooth**
允许应用通过蓝牙配件播放和录制音频。
常用于需要通过蓝牙耳机或车载系统播放音频的应用。
示例用途：支持蓝牙耳机的音乐播放器或 VoIP 应用。
4. **AVAudioSession.CategoryOptions.defaultToSpeaker**
默认情况下，将音频路由到内置扬声器，而不是电话听筒。
在 .playAndRecord 类别中特别有用，尤其是当用户没有连接蓝牙耳机时。
示例用途：VoIP 应用在没有耳机连接的情况下默认使用扬声器。
设置 AVAudioSessionCategory 选项
在设置 AVAudioSession 类别时，你可以同时指定一个或多个这样的选项：
```swift
do {
    try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
    try AVAudioSession.sharedInstance().setActive(true)
} catch {
    print("设置音频会话类别和选项失败。错误：\(error)")
}

```
#### 注意事项

- 并非所有的选项都适用于每个类别。在选择选项时，需要考虑它们是否与你选择的类别兼容。
在多任务处理环境中，合理使用这些选项可以提升用户体验，确保你的应用与其他应用和系统功能协调运作。
### AVAudioSessionSetActiveOption 
AVAudioSessionSetActiveOption在 iOS 中用于在激活或停用 AVAudioSession 时提供附加选项。这些选项可以帮助你更精细地控制音频会话的行为。以下是 AVAudioSessionSetActiveOption 的主要选项：

1. **AVAudioSessionSetActiveOption.notifyOthersOnDeactivation**
当你的应用停用音频会话时，这个选项会通知其他音频应用，使它们有机会恢复播放。
这对于那些暂时占用音频会话（例如播放一条消息或声音效果）的应用来说非常有用。
使用这个选项可以改善用户体验，尤其是在多任务处理环境中。
#### 使用示例
假设你的应用完成了一个需要独占音频的任务，比如播放了一个声音效果，现在你想停用音频会话并让其他应用恢复播放，你可以这样做：
```swift
do {
    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
} catch {
    print("停用音频会话失败。错误：\(error)")
}
```
#### 注意事项

- 使用 **notifyOthersOnDeactivation** 时，确保你的应用在停用音频会话前已经完成了所有音频播放任务。
- 记住，启用或停用音频会话可能会影响到其他正在运行的应用，因此请谨慎使用这些选项，以确保良好的用户体验。
- 当你的应用不再需要使用音频时，适时地停用音频会话是一个好习惯，这有助于节省电池和资源。

## Author

summerhearts@163.com, summerhearts@163.com

## License

AudioQueueMananger is available under the MIT license. See the LICENSE file for more info.
