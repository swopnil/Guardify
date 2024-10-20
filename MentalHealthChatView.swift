import SwiftUI
import SwiftData
import Combine

struct MentalHealthChatView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("chatMessages") private var storedMessages: Data = Data()
    @State private var messages: [ChatMessage] = []
    @State private var newMessage: String = ""
    @State private var showingSafetyAlert = false
    @State private var messageCount: Int = 0
    @State private var isTyping = false
    @State private var hasAppeared = false

    private let backgroundGradient = LinearGradient(gradient: Gradient(colors: [Color.red.opacity(0.1), Color.white]), startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack {
            backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack {
                headerView
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 15) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messageCount) { _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                typingIndicator
                
                HStack {
                    TextField("Type a message...", text: $newMessage)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.red)
                            .clipShape(Circle())
                            .shadow(color: .red.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                    .disabled(newMessage.isEmpty)
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(25)
                .padding(.horizontal)
                .padding(.bottom, 10)
  
                Button(action: startNewChat) {
                    Text("New Chat")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(15)
                }
                .padding(.bottom, 5)
            }
        }
        .navigationTitle("Mental Health Chat")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Safety Check", isPresented: $showingSafetyAlert) {
            Button("Yes") {
                contactPublicSafety()
            }
            Button("No", role: .cancel) {
                showingSafetyAlert = false
            }
        } message: {
            Text("Your message has been flagged as potentially concerning. Do you want us to contact public safety?")
        }
        .onAppear {
            if !hasAppeared {
                loadMessages()
                if messages.isEmpty {
                    addBotMessage("Hello! I'm here to chat about mental health. How are you feeling today?")
                }
                hasAppeared = true
            }
        }
    }

    private func sendMessage() {
        guard !newMessage.isEmpty else { return }
        
        let userMessage = ChatMessage(content: newMessage, isUser: true)
        withAnimation {
            messages.append(userMessage)
            messageCount += 1
        }
        
        saveMessages()
        
        isTyping = true
        sendMessageToAPI(newMessage)
        
        newMessage = ""
    }

    private func sendMessageToAPI(_ message: String) {
            guard let url = URL(string: "http://34.223.91.199:8000/chat") else {
                print("Invalid URL")
                return
            }
            
            let body: [String: String] = ["message": message]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isTyping = false
                    
                    if let error = error {
                        print("Error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = data else {
                        print("No data received")
                        return
                    }
                    
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        print("Raw API response: \(rawResponse)")
                    }
                    
                    do {
                        if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            if let botMessage = jsonResponse["bot_message"] as? String {
                                self.addBotMessage(botMessage)
                            }
                            if let isMaliciousString = jsonResponse["malicious"] as? String {
                                let isMalicious = isMaliciousString.lowercased() == "true"
                                if isMalicious {
                                    self.showingSafetyAlert = true
                                }
                            }
                        } else {
                            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
                        }
                    } catch {
                        print("Decoding error: \(error.localizedDescription)")
                        self.addBotMessage("I'm sorry, I'm having trouble understanding the response. Please try again later.")
                    }
                }
            }.resume()
        }


    private func addBotMessage(_ content: String) {
        let botMessage = ChatMessage(content: content, isUser: false)
        withAnimation {
            messages.append(botMessage)
            messageCount += 1
        }
        saveMessages()
    }

    private func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            storedMessages = data
        } catch {
            print("Failed to save messages: \(error)")
        }
    }

    private func loadMessages() {
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: storedMessages)
            messageCount = messages.count
        } catch {
            print("Failed to load messages: \(error)")
            messages = []
        }
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "heart.text.square.fill")
                .foregroundColor(.red)
                .font(.largeTitle)
            Text("MindfulChat")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(15)
        .shadow(color: .gray.opacity(0.3), radius: 5, x: 0, y: 2)
    }

    private var typingIndicator: some View {
        HStack {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(isTyping ? 1 : 0)
                    .animation(Animation.easeInOut(duration: 0.5).repeatForever().delay(0.2 * Double(index)), value: isTyping)
            }
        }
        .padding(.leading)
        .opacity(isTyping ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isTyping)
    }

    private func startNewChat() {
        withAnimation {
            messages.removeAll()
            messageCount = 0
            saveMessages()
            addBotMessage("Hello! I'm here to start a new chat about mental health. How are you feeling today?")
        }
    }

    private func contactPublicSafety() {
        let newAlert = Alert(timestamp: Date(), isEmergency: true, location: "User's location")
        modelContext.insert(newAlert)
        do {
            try modelContext.save()
            print("Alert saved successfully")
        } catch {
            print("Failed to save alert: \(error)")
        }
        
        print("Contacting public safety at 10.1.23.3/sendmessage")
        
        addBotMessage("I've notified public safety. They will be contacting you shortly. Please stay safe.")
    }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    
    init(id: UUID = UUID(), content: String, isUser: Bool) {
        self.id = id
        self.content = content
        self.isUser = isUser
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUser == rhs.isUser
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(message.isUser ? Color.red : Color.white)
                .foregroundColor(message.isUser ? .white : .black)
                .cornerRadius(20)
                .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)
            if !message.isUser { Spacer() }
        }
    }
}

struct MentalHealthChatView_Previews: PreviewProvider {
    static var previews: some View {
        MentalHealthChatView()
    }
}
