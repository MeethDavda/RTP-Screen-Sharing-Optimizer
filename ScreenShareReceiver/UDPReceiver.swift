//
//  UDPReceiver.swift
//  ScreenShareReceiver
//
//  Created by Meeth Davda on 10/02/26.
//

// ScreenShareReceiver/UDPReceiver.swift
import Foundation
import Network

final class UDPReceiver {
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "receiver.udp.queue")
    private var listener: NWListener?
    private var lastSeq:UInt16? = nil
    private var received = 0
    private var lost = 0
    private var outOfOrder = 0

    private let onLog: (String) -> Void

    init(listenPort: UInt16 = 5004, onLog: @escaping (String) -> Void = { print($0) }) {
        self.port = NWEndpoint.Port(rawValue: listenPort)!
        self.onLog = onLog
    }

    func start() throws {
        let params = NWParameters.udp
        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            self?.onLog("UDPReceiver state: \(state)")
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.startReceiving(on: conn)
        }

        listener.start(queue: queue)
        onLog("UDPReceiver listening on UDP port \(port.rawValue)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onLog("UDPReceiver stopped")
    }

    private func startReceiving(on conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.receiveLoop(conn)
            }
        }
        conn.start(queue: queue)
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.onLog("receiveMessage error: \(error)")
                return
            }
            received+=1
            
            if let data, !data.isEmpty {
                let src = self.describeEndpoint(conn.endpoint)

                if let rtp = RTPPacket.parse(data) {
                    let seq = rtp.header.sequenceNumber
                    
                    if let last = lastSeq{
                        if seq == last &+ 1{
                            print("inorder")
                        }else if seq > last{
                            let missing = Int(seq - last - 1)
                            if missing > 0{
                                lost+=missing
                                self.onLog("Loss!")
                            }
                        }else{
                            outOfOrder+=1
                            onLog("Out of order")
                        }
                        if seq > last{
                            lastSeq = seq
                        }
                    }else{
                        lastSeq = seq
                    }
                    
                    self.onLog("[RTP] from \(src) seq=\(seq) bytes=\(data.count)")
                } else {
                    self.onLog("[UDP] from \(src) non-RTP bytes=\(data.count)")
                }
            }

            self.receiveLoop(conn)
        }
    }

    private func describeEndpoint(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return "\(endpoint)"
        }
    }
}

