//
//  ScreenShareSenderApp.swift
//  ScreenShareSender
//
//  Created by Meeth Davda on 10/02/26.
//

import SwiftUI

@main
struct ScreenShareSenderApp: App {
    private let control = UDPControlListener(listenPort: 5000)
    private let sender = UDPSender(receiverIP: "127.0.0.1", port: 5004)
    
    init(){
        do{
            control.onMessage = {[weak sender] msg in
                if msg == "KEYFRAME_REQUEST"{
                    print("Forcing keyframe due to receiver request")
                    sender?.sendKeyframeMarker()
                }
            }
            try control.start()
        }catch{
            print("Control listener failed:", error)
        }
        
    }
    
    var body: some Scene {
        WindowGroup {
            SenderContentView(sender: sender)
        }
    }
}
