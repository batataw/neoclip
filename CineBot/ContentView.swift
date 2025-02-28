import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Speech

struct ContentView: View {
    @State private var player = AVPlayer()
    @State private var asset: AVAsset?
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var showAlert: Bool = false
    @State private var transcriptionText: String = ""
    @State private var isTranscribing: Bool = false
    @State private var recognitionTask: SFSpeechRecognitionTask?


    var body: some View {
        HStack {
            // Video Player on the left
            VStack {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()

                // Barre de progression vidéo
                Slider(value: $currentTime, in: 0...videoDuration, onEditingChanged: { isEditing in
                    if !isEditing {
                        let newTime = CMTime(seconds: currentTime, preferredTimescale: 600)
                        player.seek(to: newTime)
                    }
                })
                .padding()
                
                // Boutons de contrôle vidéo alignés à gauche
                HStack(spacing: 20) {
                    
                    Button(action: {
                        if let fileURL = openFileDialog() {
                            loadVideo(url: fileURL)
                        }
                    }) {
                        Image(systemName: "folder.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    
                    Button(action: {
                        player.pause()
                        player.seek(to: .zero)
                        isPlaying = false
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // New transcription button
                    Button(action: {
                        if asset == nil {
                            showAlert = true
                        } else {
                            transcript()
                        }
                    }) {
                        Image(systemName: "text.bubble.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
                .padding()
            }
            .frame(maxWidth: .infinity)

            // Transcription area on the right
            VStack {
                ScrollView {
                      if isTranscribing {
                          VStack {
                              ProgressView()
                                  .padding()
                              Text(transcriptionText)
                                  .padding()
                                  .frame(maxWidth: .infinity, alignment: .leading)
                          }
                      } else {
                          Text(transcriptionText.isEmpty ? "No transcription available yet. Click the transcription button to start." : transcriptionText)
                              .padding()
                              .frame(maxWidth: .infinity, alignment: .leading)
                      }
                  }
                  .padding()
                  Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
        }
        .onAppear {
            addPeriodicTimeObserver()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("No Video Loaded"), message: Text("Please load a video before starting transcription."), dismissButton: .default(Text("OK")))
        }
    }
    
    // Charger la vidéo
    private func loadVideo(url: URL) {
        let videoAsset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: videoAsset)
        player.replaceCurrentItem(with: playerItem)
        asset = videoAsset
        videoURL = url
        
        // Load the duration asynchronously
        videoAsset.loadValuesAsynchronously(forKeys: ["duration"]) {
            var error: NSError? = nil
            let status = videoAsset.statusOfValue(forKey: "duration", error: &error)
            if status == .loaded {
                DispatchQueue.main.async {
                    videoDuration = CMTimeGetSeconds(videoAsset.duration)
                    currentTime = 0
                    isPlaying = false
                }
            } else {
                print("Failed to load duration: \(String(describing: error?.localizedDescription))")
            }
        }
    }
    
    // Observer pour suivre la progression de la vidéo
    private func addPeriodicTimeObserver() {
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: time, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }
    }

    
    // Replace your transcript() function with this simplified version
    private func transcript() {
        guard let videoURL = videoURL else {
            transcriptionText = "No video URL available."
            return
        }
        
        // Update UI
        isTranscribing = true
        transcriptionText = "Starting transcription process..."
        
        // Create a temporary file URL for the audio
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("audio_for_transcription.m4a")
        
        // Remove any existing file at that URL
        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                try FileManager.default.removeItem(at: audioURL)
            } catch {
                DispatchQueue.main.async {
                    self.transcriptionText = "Error removing temporary file: \(error.localizedDescription)"
                    self.isTranscribing = false
                }
                return
            }
        }
        
        // Create a composition with just the audio track
        let composition = AVMutableComposition()
        
        // Load the asset (we already have it but let's ensure it's loaded)
        let asset = AVAsset(url: videoURL)
        
        // Add audio track to composition
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
                DispatchQueue.main.async {
                    self.transcriptionText = "Failed to create audio track for export."
                    self.isTranscribing = false
                }
                return
        }
        
        // Find the first audio track in the original asset
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            
            if status != .loaded {
                DispatchQueue.main.async {
                    self.transcriptionText = "Failed to load asset tracks: \(error?.localizedDescription ?? "Unknown error")"
                    self.isTranscribing = false
                }
                return
            }
            
            let audioTracks = asset.tracks(withMediaType: .audio)
            
            guard let sourceAudioTrack = audioTracks.first else {
                DispatchQueue.main.async {
                    self.transcriptionText = "No audio track found in video."
                    self.isTranscribing = false
                }
                return
            }
            
            do {
                // Insert the entire audio track into our composition
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: asset.duration),
                    of: sourceAudioTrack,
                    at: .zero
                )
                
                // Create export session
                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetAppleM4A) else {
                        DispatchQueue.main.async {
                            self.transcriptionText = "Failed to create export session."
                            self.isTranscribing = false
                        }
                        return
                }
                
                // Configure export
                exportSession.outputURL = audioURL
                exportSession.outputFileType = .m4a
                
                // Update UI
                DispatchQueue.main.async {
                    self.transcriptionText = "Extracting audio..."
                }
                
                // Start the export
                exportSession.exportAsynchronously {
                    switch exportSession.status {
                    case .completed:
                        DispatchQueue.main.async {
                            self.transcriptionText = "Audio extracted, starting recognition..."
                            self.performSpeechRecognition(on: audioURL)
                        }
                    case .failed:
                        DispatchQueue.main.async {
                            self.transcriptionText = "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"
                            self.isTranscribing = false
                        }
                    case .cancelled:
                        DispatchQueue.main.async {
                            self.transcriptionText = "Export cancelled."
                            self.isTranscribing = false
                        }
                    default:
                        DispatchQueue.main.async {
                            self.transcriptionText = "Export ended with status: \(exportSession.status.rawValue)"
                            self.isTranscribing = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.transcriptionText = "Error setting up audio export: \(error.localizedDescription)"
                    self.isTranscribing = false
                }
            }
        }
    }

    // Helper function to perform speech recognition
    private func performSpeechRecognition(on audioURL: URL) {
        // Request authorization first
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.transcriptionText = "Speech recognition not authorized: \(status.rawValue)"
                    self.isTranscribing = false
                    return
                }
                
                // Create the recognizer
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")) else {
                    self.transcriptionText = "Reconnaissance vocale non disponible pour le français."
                    self.isTranscribing = false
                    return
                }
                    
                // Create the recognition request
                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.shouldReportPartialResults = true
                
                // Start recognition
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.transcriptionText = "Recognition error: \(error.localizedDescription)"
                            self.isTranscribing = false
                        }
                        return
                    }
                    
                    guard let result = result else { return }
                    
                    DispatchQueue.main.async {
                        // Update with partial results
                        let transcription = result.bestTranscription.formattedString
                        self.transcriptionText = transcription
                        
                        // If this is the final result, mark as complete
                        if result.isFinal {
                            self.isTranscribing = false
                        }
                    }
                }
                
                // Store task for potential cancellation if needed
                self.recognitionTask = task
            }
        }
    }

}

#Preview {
    ContentView()
}

// Ouvrir un fichier vidéo
func openFileDialog() -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [UTType.movie, UTType.mpeg4Movie, UTType.quickTimeMovie]
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = false

    if openPanel.runModal() == .OK {
        return openPanel.url
    }
    return nil
}
