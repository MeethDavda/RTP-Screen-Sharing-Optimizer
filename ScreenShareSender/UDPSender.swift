//
//  UDPSender.swift
//  ScreenShareSender
//
//  Created by Meeth Davda on 10/02/26.
//

import Foundation
import Network

final class UDPSender {
    private let conn: NWConnection
    private var seq: UInt16 = 1

    init(receiverIP: String, port: UInt16 = 5004) {
        conn = NWConnection(
            host: NWEndpoint.Host(receiverIP),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )
        conn.start(queue: .global())
    }

    func sendOnePacket() {
        let packet = buildRTPPacket(seq: seq)
        conn.send(content: packet, completion: .contentProcessed { _ in })
        print("➡️ Sent RTP seq=\(seq)")
        seq += 1
        //for testing Loss
        if seq%10 == 0 {seq+=1}
    }

    private func buildRTPPacket(seq: UInt16) -> Data {
        var d = Data()

        // RTP v2, no padding/extension/CSRC
        d.append(0x80)

        // Marker=1, PayloadType=96
        d.append(0xE0)

        d.appendUInt16BE(seq)
        d.appendUInt32BE(12345)        // dummy timestamp
        d.appendUInt32BE(0x12345678)   // dummy SSRC

        d.append(Data(repeating: 0xAA, count: 20)) // dummy payload
        return d
    }
}

private extension Data {
    mutating func appendUInt16BE(_ v: UInt16) {
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8(v & 0xFF))
    }

    mutating func appendUInt32BE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8(v & 0xFF))
    }

    mutating func append(_ b: UInt8) {
        append(contentsOf: [b])
    }
}

