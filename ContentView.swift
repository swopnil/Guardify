import SwiftUI
import SwiftData
import Speech
import AVFoundation
import MapKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var alerts: [Alert]
    @State private var isListening = false
    @State private var isRecording = false
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var uploadTimer: Timer?
    @State private var currentTranscription = ""
    @State private var selectedTab = 0
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private let audioEngine = AVAudioEngine()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            EmergencyView(isListening: $isListening, isRecording: $isRecording, toggleListening: toggleListening)
                .tabItem {
                    Label("Emergency", systemImage: "exclamationmark.triangle.fill")
                }
                .tag(0)
            
            CampusMapView()
                .tabItem {
                    Label("Campus Map", systemImage: "map.fill")
                }
                .tag(1)
            
            MentalHealthChatView()
                .tabItem {
                    Label("Mental Health", systemImage: "heart.text.square.fill")
                }
                .tag(2)
        }
        .accentColor(.red)
        .onAppear(perform: setupSpeech)
    }
    private func setupSpeech() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    print("Speech recognition authorized")
                } else {
                    print("Speech recognition not authorized")
                }
            }
        }
    }
    
    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    private func startListening() {
        guard !isListening else { return }
        
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create recognition request")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.currentTranscription = result.bestTranscription.formattedString
                if self.currentTranscription.lowercased().contains("1234") && !self.isRecording {
                    print("Detected '1234', starting recording")
                    self.startRecording()
                }
            }
            if error != nil {
                self.stopListening()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }
        
        isListening = true
    }
    
    private func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isListening = false
        
        if isRecording {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        currentTranscription = ""
        
        // Start a timer to send transcribed text every 10 seconds
        uploadTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.sendTranscriptionToServer()
        }
        
        // Schedule stopping the recording after 1 minute (6 uploads)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            self.stopRecording()
        }
    }
    
    private func stopRecording() {
        isRecording = false
        
        // Invalidate and remove the upload timer
        uploadTimer?.invalidate()
        uploadTimer = nil
        
        // Send the final transcription to the server
        sendTranscriptionToServer()
    }
    
    private func sendTranscriptionToServer() {
        guard !currentTranscription.isEmpty else {
            print("No transcription to send")
            return
        }
        
        guard let url = URL(string: "http://54.212.239.210:5000/detect") else {
            print("Error: Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["transcription": currentTranscription]
        
        do {
            print("Sending payload: \(payload)")
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                print("\n--- API Response ---")
                if let error = error {
                    print("Error sending transcription: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Response Status code: \(httpResponse.statusCode)")
                }
                
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Server response: \(responseString)")
                } else {
                    print("No response data received")
                }
                print("--------------------\n")
            }
            
            task.resume()
            print("Transcription upload task started")
            
            // Clear the current transcription after sending
            currentTranscription = ""
        } catch {
            print("Error preparing transcription data: \(error)")
        }
    }
}
struct EmergencyView: View {
    @Binding var isListening: Bool
    @Binding var isRecording: Bool
    var toggleListening: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.red.opacity(0.1), Color.orange.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Text("Emergency Alert")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                
                Button(action: toggleListening) {
                    ZStack {
                        Circle()
                            .fill(isListening ? Color.green : Color.red)
                            .frame(width: 180, height: 180)
                            .shadow(color: isListening ? .green : .red, radius: 10, x: 0, y: 5)
                        
                        Image(systemName: isListening ? "checkmark.shield.fill" : "shield.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                    }
                }
                
                Text(isListening ? "Safety Track Mode On" : "Tap to Activate Safety Track")
                    .font(.headline)
                    .foregroundColor(isListening ? .green : .red)
                
                if isRecording {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("Recording in progress")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(20)
                }
                
                Spacer()
                
                Text("In case of emergency, speak clearly and describe your situation.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Alert.self, inMemory: true)
}
