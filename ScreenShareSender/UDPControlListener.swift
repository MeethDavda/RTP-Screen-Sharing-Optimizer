//
//  UDPControlListener.swift
//  ScreenShareSender
//
//  Created by Meeth Davda on 16/02/26.
//

import Foundation
import Network

final class UDPControlListener{
    private let port:NWEndpoint.Port
    private let queue = DispatchQueue(label: "sender.control.queue")
    private var listener:NWListener?
    
    init(listenPort: UInt16 = 5000) {
            self.port = NWEndpoint.Port(rawValue: listenPort)!
        }

        func start() throws {
            let l = try NWListener(using: .udp, on: port)
            listener = l

            l.stateUpdateHandler = { state in
                print("[CTRL] listener state:", state)
            }

            l.newConnectionHandler = { conn in
                conn.start(queue: self.queue)
                self.receiveLoop(conn)
            }

            l.start(queue: queue)
            print("[CTRL] listening on UDP \(port.rawValue)")
        }
    
    func stop() {
           listener?.cancel()
           listener = nil
            print("UDPReceiver stopped")
       }
    private func receiveLoop(_ conn: NWConnection) {
            conn.receiveMessage { data, _, _, error in
                if let error {
                    print("[CTRL] receive error:", error)
                    return
                }
                if let data, let msg = String(data: data, encoding: .utf8) {
                    print("[CTRL] received:", msg)
                }
                self.receiveLoop(conn)
            }
        }
}
