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
    private let windowSize = 200
    private var lossRing: [Int] = Array(repeating:0,count:200)
    private var recvRing: [Int] = Array(repeating:0,count:200)
    private var winLost: Int = 0
    private var winRecv: Int = 0
    private var ringIndex: Int = 0
    

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
    
    private func pushWindow(loss:Int, recv:Int){
        winLost -= lossRing[ringIndex]
        winRecv -= recvRing[ringIndex]
        
        lossRing[ringIndex] = loss
        recvRing[ringIndex] = recv
        
        winLost += loss
        winRecv += recv
        
        ringIndex = (ringIndex+1)%windowSize
    }
    
    private var rollingLossRate: Double{
        let denom = winLost + winRecv
        if denom == 0 {return 0.0}
        
        return Double(winLost)/Double(denom)
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
            
            
            if let data, !data.isEmpty {
                let src = self.describeEndpoint(conn.endpoint)
                
                if let rtp = RTPPacket.parse(data) {
                    received+=1
                    let seq = rtp.header.sequenceNumber
                    
                    if let last = lastSeq{
                        if seq == last &+ 1{
                            print("inorder")
                            pushWindow(loss: 0, recv: 1)
                            lastSeq = seq
                        }else if seq > last{
                            let missing = Int(seq - last - 1)
                            if missing > 0{
                                lost+=missing
                                self.onLog("Loss!")
                            }
                            pushWindow(loss: missing, recv: 1)
                            lastSeq = seq
                        }else{
                            outOfOrder+=1
                            onLog("Out of order")
                        }
                    }else{
                        lastSeq = seq
                        pushWindow(loss: 0, recv: 1)
                    }
                    
                    self.onLog("[RTP] from \(src) seq=\(seq) bytes=\(data.count)")
                } else {
                    self.onLog("[UDP] from \(src) non-RTP bytes=\(data.count)")
                }
                if received % 20 == 0 {
                    let rate = rollingLossRate * 100.0
                    onLog("📊 Rolling loss (~\(windowSize) events): \(String(format: "%.2f", rate))% | total lost=\(lost) ooo=\(outOfOrder)")
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

