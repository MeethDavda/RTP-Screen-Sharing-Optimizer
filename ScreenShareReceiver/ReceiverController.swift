//
//  ReceiverController.swift
//  ScreenShareReceiver
//
//  Created by Meeth Davda on 10/02/26.
//

import Foundation
import Combine

@MainActor
final class ReceiverController: ObservableObject {
    private var receiver: UDPReceiver?

    @Published private(set) var isRunning: Bool = false
    @Published var lastLogLine: String = ""

    func start(listenPort: UInt16 = 5004) {
        guard !isRunning else { return }

        let r = UDPReceiver(listenPort: listenPort) { [weak self] line in
            // 1) Print to Xcode console
            print(line)
            // Called on receiver's queue; hop to main for UI/state
            DispatchQueue.main.async {
                self?.lastLogLine = line
            }
        }
        receiver = r

        do {
            try r.start()
            isRunning = true
            lastLogLine = "Listening on UDP \(listenPort)"
        } catch {
            isRunning = false
            lastLogLine = "Failed to start receiver: \(error)"
        }
    }

    func stop() {
        receiver?.stop()
        receiver = nil
        isRunning = false
        lastLogLine = "Stopped"
    }
}

