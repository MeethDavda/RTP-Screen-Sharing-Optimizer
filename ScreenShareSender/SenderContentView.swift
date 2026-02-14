//
//  ContentView.swift
//  ScreenShareSender
//
//  Created by Meeth Davda on 10/02/26.
//

import SwiftUI

struct SenderContentView: View {
    @State private var sender = UDPSender(receiverIP: "127.0.0.1")

        var body: some View {
            VStack(spacing: 16) {
                Text("Simple RTP Sender")
                    .font(.title2)

                Button("Send RTP Packet") {
                    sender.sendOnePacket()
                }
            }
            .padding()
            .frame(width: 300, height: 200)
        }
}

#Preview {
    SenderContentView()
}
