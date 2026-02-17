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
    
    init(){
        try? control.start()
    }
    
    var body: some Scene {
        WindowGroup {
            SenderContentView()
        }
    }
}
