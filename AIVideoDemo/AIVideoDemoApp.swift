//
//  AIVideoDemoApp.swift
//  AIVideoDemo
//
//  Created by Martin Mitrevski on 10.2.25.
//

import SwiftUI
import StreamVideo
import StreamVideoSwiftUI

@main
struct AIVideoDemoApp: App {
    
    @State var streamVideo: StreamVideo?
    @State var call: Call?
    
    @State var currentLevel: CGFloat = 0
    @State var aiParticipant: CallParticipant?
    @State var credentials: Credentials?
    @State var connectTask: Task<Void, Error>?
    @State var callState: AICallState = .idle
    @State private var captions: [CallClosedCaption] = []
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if callState == .active, let call {
                    AISpeakingView(callState: call.state)
                        .overlay(
                            VStack {
                                Spacer()
                                VStack {
                                    ForEach(captions, id: \.hashValue) { item in
                                        VStack(alignment: .leading) {
                                            Text(item.speakerId)
                                                .font(.caption)
                                                .bold()
                                            HStack {
                                                Text(item.text)
                                                    .lineLimit(3)
                                                Spacer()
                                            }
                                        }
                                        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top)))
                                    }

                                    HStack {
                                        Spacer()
                                        StatelessHangUpIconView(call: call) {
                                            call.leave()
                                            self.call = nil
                                            self.callState = .idle
                                        }
                                    }
                                }
                                .padding()
                            }
                            .onReceive(call.state.$closedCaptions) { captions = $0 }
                        )
                } else if callState == .joining {
                    HStack {
                        Text("Waiting for AI agent to join...")
                        ProgressView()
                    }
                } else {
                    Button {
                        Task {
                            do {
                                self.callState = .joining
                                _ = await connectTask?.result
                                guard let credentials, let streamVideo else { return }
                                self.call = streamVideo.call(
                                    callType: credentials.callType,
                                    callId: credentials.callId
                                )
                                try await call?.join(create: true)
                                call?.updateStatsCollectionInterval(0.25)
                                self.callState = .active
                            } catch {
                                print(error)
                                self.callState = .idle
                            }
                        }
                    } label: {
                        Text("Click to talk to AI")
                            .padding()
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear {
                connectTask = Task {
                    try await connect()
                }
            }
        }
        
    }
    
    func connect() async throws {
        let credentials = try await fetchCredentials()
        let user = User(id: credentials.userId)

        let streamVideo = StreamVideo(
            apiKey: credentials.apiKey,
            user: user,
            token: .init(rawValue: credentials.token)
        )
        
        self.streamVideo = streamVideo
        self.credentials = credentials
        
        try await streamVideo.connect()
    }

    func fetchCredentials() async throws -> Credentials {
        let urlSession = URLSession.shared
        let url = URL(string: "https://stream-openai-d0716d0c2d64.herokuapp.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let data = try await urlSession.data(for: request).0 as Data
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
}

enum AICallState {
    case idle
    case joining
    case active
}

struct Credentials: Codable {
    let apiKey: String
    let token: String
    let cid: String
    
    var callType: String {
        cid.components(separatedBy: ":").first ?? ""
    }
    
    var callId: String {
        cid.components(separatedBy: ":").last ?? ""
    }
    
    var userId: String {
        parseUserIdFromToken(token)
    }
    
    func parseUserIdFromToken(_ token: String) -> String {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return "" }
        
        let payload = String(parts[1])
        
        // Convert Base64URL to standard Base64
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        guard let decodedData = Data(base64Encoded: base64),
              let jsonObject = try? JSONSerialization.jsonObject(with: decodedData, options: []),
              let jsonDict = jsonObject as? [String: Any],
              let userId = jsonDict["user_id"] as? String else {
            return ""
        }
        
        return userId
    }
}
