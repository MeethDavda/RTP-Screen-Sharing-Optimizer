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
    
    // Jitter buffer variabls
    private var buffer: [UInt16:RTPPacket] = [:]
    private var expectedSeq: UInt16? = nil
    private var missingSince: Date? = nil
    private var missingTimeout: TimeInterval = 0.04
    private var playoutTimer: DispatchSourceTimer?
    
    private enum NetworkState{
        case good
        case degraded
        case bad
    }
    private var currentState: NetworkState = .good
    
    private var lastSenderHost: NWEndpoint.Host?
    private let controlPort: NWEndpoint.Port = 5000
    

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
        
        startPlayoutTimer()
    }

    func stop() {
        playoutTimer?.cancel()
        playoutTimer = nil
        
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
    
    private func startPlayoutTimer() {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(5))
            t.setEventHandler { [weak self] in
                self?.timeoutTick()
            }
            t.resume()
            playoutTimer = t
    }
    
    private func timeoutTick(){
        guard let exp = expectedSeq else {return}
        
        if let _ = buffer.removeValue(forKey: exp){
            received+=1
            pushWindow(loss: 0, recv: 1)
            onLog("RELEASE seq=\(exp)")
            evaluateNetworkState()
            expectedSeq = exp &+ 1
            missingSince = nil
            
            if received % 20 == 0 {
                            let rate = rollingLossRate * 100.0
                            onLog("Rolling loss (~\(windowSize) events): \(String(format: "%.2f", rate))% | lost=\(lost) ooo=\(outOfOrder)")
            }
            return
        }
        
        if missingSince == nil{
            missingSince = Date()
            return
        }
        
        if let start = missingSince, Date().timeIntervalSince(start) >= missingTimeout{
            lost+=1
            pushWindow(loss: 1, recv: 1)
            onLog("MISSING seq=\(exp)")
            expectedSeq = exp &+ 1
            missingSince = nil
            if received % 20 == 0 {
                            let rate = rollingLossRate * 100.0
                            onLog("Rolling loss (~\(windowSize) events): \(String(format: "%.2f", rate))% | lost=\(lost) ooo=\(outOfOrder)")
            }
            return
        }
    }
    
    private func evaluateNetworkState(){
        let lossPercent = rollingLossRate * 100.0
        let newState: NetworkState
        
        if lossPercent < 3{
            newState = .good
        }else if lossPercent < 10{
            newState = .degraded
        }else{
            newState = .bad
        }
        
        if newState != currentState{
            currentState = newState
            switch newState{
            case .good:
                onLog("Network GOOD (\(String(format: "%.2f", lossPercent))%)")
            case .degraded:
                onLog("Network DEGRADED (\(String(format: "%.2f", lossPercent))%)")
            case .bad:
                onLog("Network BAD (\(String(format: "%.2f", lossPercent))%)")
                sendControl("KEYFRAME_REQUEST")
            }
        }
    }
    
    private func sendControl(_ message:String){
        guard let host = lastSenderHost else {return}
        
        let conn = NWConnection(host: host, port: controlPort, using: .udp)
        conn.start(queue: queue)
        
        let data = message.data(using: .utf8)!
        
        conn.send(content: data, completion: .contentProcessed { _ in
                conn.cancel()
            })

        onLog("Sent CONTROL '\(message)' to \(host):\(controlPort.rawValue)")
        
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
                if case let .hostPort(host, _) = conn.endpoint {
                    lastSenderHost = host
                }
                
                if let rtp = RTPPacket.parse(data) {
                    received+=1
                    let seq = rtp.header.sequenceNumber
                    
                    if expectedSeq == nil {expectedSeq = seq}
                    
                    if let exp=expectedSeq,seq < exp{
                        outOfOrder+=1
                    }
                    buffer[seq] = rtp
                    self.onLog("[ARRIVE] from \(src) seq=\(seq)")
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

