//
//  Screen_share_optimiserApp.swift
//  Screen share optimiser
//
//  Created by Meeth Davda on 10/02/26.
//

import SwiftUI

@main
struct ScreenShareReceiverApp: App {
    @StateObject var controller = ReceiverController()
    
    var body: some Scene {
        WindowGroup {
            ReceiverContentView()
                .environmentObject(controller)
                .onAppear {
                    print("✅ ReceiverContentView onAppear()")
                    controller.start(listenPort: 5004)
                }
        }
    }
}
