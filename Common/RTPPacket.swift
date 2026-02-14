//
//  RTPPacket.swift
//  ScreenShareOptimiser
//
//  Created by Meeth Davda on 10/02/26.
//

import Foundation

public struct RTPPacket {
    public struct Header {
        public let version: UInt8
        public let padding: Bool
        public let hasExtension: Bool
        public let csrcCount: UInt8
        public let marker: Bool
        public let payloadType: UInt8
        public let sequenceNumber: UInt16
        public let timestamp: UInt32
        public let ssrc: UInt32
        public let headerLengthBytes: Int
    }

    public let header: Header
    public let payload: Data

    public static func parse(_ data: Data) -> RTPPacket? {
        guard data.count >= 12 else { return nil }

        let b0 = data[0]
        let version = (b0 >> 6) & 0b11
        guard version == 2 else { return nil }

        let padding = ((b0 >> 5) & 0b1) == 1
        let hasExtension = ((b0 >> 4) & 0b1) == 1
        let csrcCount = b0 & 0b1111

        let b1 = data[1]
        let marker = ((b1 >> 7) & 0b1) == 1
        let payloadType = b1 & 0b0111_1111

        let seq = readUInt16BE(data, 2)
        let ts  = readUInt32BE(data, 4)
        let ssrc = readUInt32BE(data, 8)

        var offset = 12 + Int(csrcCount) * 4
        guard data.count >= offset else { return nil }

        if hasExtension {
            guard data.count >= offset + 4 else { return nil }
            let extLenWords = readUInt16BE(data, offset + 2)
            offset += 4 + Int(extLenWords) * 4
            guard data.count >= offset else { return nil }
        }

        let hdr = Header(
            version: version,
            padding: padding,
            hasExtension: hasExtension,
            csrcCount: csrcCount,
            marker: marker,
            payloadType: payloadType,
            sequenceNumber: seq,
            timestamp: ts,
            ssrc: ssrc,
            headerLengthBytes: offset
        )

        return RTPPacket(header: hdr, payload: data.subdata(in: offset..<data.count))
    }
}

@inline(__always)
private func readUInt16BE(_ data: Data, _ offset: Int) -> UInt16 {
    let b0 = UInt16(data[offset])
    let b1 = UInt16(data[offset + 1])
    return (b0 << 8) | b1
}

@inline(__always)
private func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1])
    let b2 = UInt32(data[offset + 2])
    let b3 = UInt32(data[offset + 3])
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

