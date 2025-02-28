import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Speech

struct TranscriptionSegment: Identifiable {
    let id = UUID()
    let text: String
    let start: String
    let stop: String
    let startTimestamp: Double
    let endTimestamp: Double
}

struct ContentView: View {
    @State private var player = AVPlayer()
    @State private var asset: AVAsset?
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var showAlert: Bool = false
    @State private var transcriptionText: String = ""
    @State private var transcriptionSegments: [TranscriptionSegment] = []

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
                Text("Transcription")
                    .font(.headline)
                    .padding()
                ScrollView {
                    ForEach(transcriptionSegments) { segment in
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Start: \(segment.start) (\(segment.startTimestamp)s)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("Stop: \(segment.stop) (\(segment.endTimestamp)s)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Text(segment.text)
                                .padding(.leading, 5)
                                .font(.body)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
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

    // Function to handle transcription
    private func transcript() {
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