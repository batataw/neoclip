import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Speech


// Ajout d'une structure pour stocker les segments avec horodatage
struct TranscriptionSegment: Identifiable {
    var id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var isActive: Bool = true 
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
    @State private var isTranscribing: Bool = false
    @State private var recognitionTask: SFSpeechRecognitionTask?
    // Ajoutez ces variables d'état à votre ContentView
    @State private var transcriptionSegments: [TranscriptionSegment] = []
    @State private var formattedTranscription: String = ""
    @State private var isPlayingSelectedSegments: Bool = false
    @State private var currentSegmentIndex: Int = 0
    @State private var playbackTimer: Timer?
    @State private var selectedEffect: String = "SANS" // Default effect


    var body: some View {
        HStack {
            // Video Player on the left
            VStack {
                // Remplacer le Text simple par une banner
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(height: 60)
                    
                    Text("LECTEUR VIDÉO")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                }
                
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

// Zone de transcription à droite
VStack {
    // Remplacer le Text simple par une banner
    ZStack {
        Rectangle()
            .fill(Color.green.opacity(0.2))
            .frame(height: 60)
        
        Text("TRANSCRIPTION")
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.green)
    }

    // Add a Picker for selecting the effect
    Picker("Effet", selection: $selectedEffect) {
        Text("SANS").tag("SANS")
        Text("JUMP CUT").tag("JUMP CUT")
        Text("ZOOM").tag("ZOOM")
    }
    .pickerStyle(SegmentedPickerStyle())
    .padding()
    .background(Color.green.opacity(0.2)) // Match the transcription banner color
    .cornerRadius(8)
    .shadow(color: .gray, radius: 3, x: 0, y: 2)
    .padding(.horizontal)
    
    if isTranscribing {
        ScrollView {
            if isTranscribing {
                VStack {
                    ProgressView()
                        .padding()
                    Text(transcriptionText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(5) // Améliore la lisibilité des lignes
                }
            } else if !transcriptionText.isEmpty {
                // Texte formaté avec les sauts de ligne et la ponctuation
                Text(transcriptionText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(5)
            } else {
                Text("Pas encore de transcription disponible. Cliquez sur le bouton de transcription pour commencer.")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
    
// Modifiez la partie affichant les segments dans l'interface utilisateur
if !transcriptionSegments.isEmpty && !isTranscribing {
    Divider()
    
    VStack(alignment: .leading) {
        
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(transcriptionSegments.indices, id: \.self) { index in
                    Button(action: {
                        // Toggle l'état d'activation du segment
                        transcriptionSegments[index].isActive.toggle()
                        // Mettre à jour la transcription formatée basée sur les segments actifs
                        updateFormattedTranscription()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "%.1fs - %.1fs", transcriptionSegments[index].startTime, transcriptionSegments[index].endTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                // Indicateur visuel de l'état d'activation
                                Image(systemName: transcriptionSegments[index].isActive ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(transcriptionSegments[index].isActive ? .green : .gray)
                            }
                            Text(transcriptionSegments[index].text)
                                .font(.body)
                                .foregroundColor(transcriptionSegments[index].isActive ? .primary : .gray)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(transcriptionSegments[index].isActive ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    // Ajouter une fonctionnalité de double-clic pour naviguer au temps du segment
                    .onTapGesture(count: 2) {
                        navigateToSegment(transcriptionSegments[index])
                    }
                }
            }
            .padding()
        }
    }
}
    Spacer()
    
    // Ajoutez le bouton de lecture en bas à droite
        if !transcriptionSegments.isEmpty && !isTranscribing {
            Spacer()
            
            HStack {
                Spacer()
                
                Button(action: {
                    // Lorsque le bouton est cliqué, nous allons lancer la lecture des segments sélectionnés
                    togglePlaySelectedSegments()
                }) {
                    HStack {
                        Image(systemName: isPlayingSelectedSegments ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.green)                        
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 20)
                .padding(.trailing, 20)
            }
        }
    
}
.frame(maxWidth: .infinity)
.background(Color.gray.opacity(0.1))
        }
        .onDisappear {
            // Invalider le timer quand la vue disparaît
            playbackTimer?.invalidate()
            playbackTimer = nil
            
            // Nettoyer d'autres ressources si nécessaire
            player.pause()
            recognitionTask?.cancel()
            recognitionTask = nil
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
                    // Démarrer la lecture automatiquement
                    player.play()
                    isPlaying = true
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

    // Ajoutez cette fonction à votre ContentView
    private func navigateToSegment(_ segment: TranscriptionSegment) {
        // Créer un CMTime à partir du temps de début du segment
        let time = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        
        // Naviguer vers ce temps dans la vidéo
        player.seek(to: time)
        
        // Mettre à jour le temps actuel
        currentTime = segment.startTime
    }
    
    // Ajoutez cette fonction à votre ContentView
    private func updateFormattedTranscription() {
        // Filtrer uniquement les segments actifs
        let activeSegments = transcriptionSegments.filter { $0.isActive }
        
        // Recréer la transcription formatée à partir des segments actifs
        formattedTranscription = processTranscriptionSegments(activeSegments)
        
        // Mettre à jour le texte affiché
        transcriptionText = formattedTranscription
    }

    
    // Replace your transcript() function with this simplified version
    private func transcript() {
        guard let videoURL = videoURL else {
            transcriptionText = "No video URL available."
            return
        }
        
        // Arrêter la lecture vidéo si elle est en cours
        if isPlaying {
            player.pause()
            isPlaying = false
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


    // Ajoutez cette fonction pour créer des segments de phrases à partir des segments originaux
    private func createPhraseSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !segments.isEmpty else { return [] }
        
        var phrases: [TranscriptionSegment] = []
        var currentPhraseText = ""
        var phraseStartTime = segments[0].startTime
        var phraseEndTime = segments[0].endTime
        
        // Configuration des seuils de pause (utilisez les mêmes que dans processTranscriptionSegments)
        let longPauseThreshold: TimeInterval = 0.4
        let mediumPauseThreshold: TimeInterval = 0.2
        
        for (index, segment) in segments.enumerated() {
            // Si ce n'est pas le premier segment, analysez la pause
            if index > 0 {
                let pauseDuration = segment.startTime - segments[index-1].endTime
                
                // Si c'est une longue pause, on termine la phrase actuelle
                if pauseDuration > longPauseThreshold {
                    // Créer une nouvelle phrase avec le texte accumulé
                    if !currentPhraseText.isEmpty {
                        let phrase = TranscriptionSegment(
                            text: currentPhraseText,
                            startTime: phraseStartTime,
                            endTime: segments[index-1].endTime
                        )
                        phrases.append(phrase)
                        
                        // Réinitialiser pour la nouvelle phrase
                        currentPhraseText = ""
                        phraseStartTime = segment.startTime
                    }
                }
            }
            
            // Ajouter le texte du segment à la phrase en cours
            if !currentPhraseText.isEmpty && !currentPhraseText.hasSuffix(" ") {
                currentPhraseText += " "
            }
            currentPhraseText += segment.text
            phraseEndTime = segment.endTime
            
            // Si c'est le dernier segment, on ajoute la phrase en cours
            if index == segments.count - 1 && !currentPhraseText.isEmpty {
                let phrase = TranscriptionSegment(
                    text: currentPhraseText,
                    startTime: phraseStartTime,
                    endTime: phraseEndTime,
                    isActive: true
                )
                phrases.append(phrase)
            }
            
        }
        
        return phrases
    }

    // Modifiez la fonction performSpeechRecognition pour utiliser les phrases
    private func performSpeechRecognition(on audioURL: URL) {
        // Demander l'autorisation d'abord
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.transcriptionText = "Reconnaissance vocale non autorisée: \(status.rawValue)"
                    self.isTranscribing = false
                    return
                }
                
                // Créer le recognizer avec la locale française
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")) else {
                    self.transcriptionText = "Reconnaissance vocale non disponible pour le français."
                    self.isTranscribing = false
                    return
                }
                
                // Créer la requête de reconnaissance
                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                
                // Activer les métadonnées de segmentation
                request.shouldReportPartialResults = true
                request.taskHint = .dictation
                
                // Vider les segments précédents
                self.transcriptionSegments = []
                
                // Démarrer la reconnaissance
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.transcriptionText = "Erreur de reconnaissance: \(error.localizedDescription)"
                            self.isTranscribing = false
                        }
                        return
                    }
                    
                    guard let result = result else { return }
                    
                    DispatchQueue.main.async {
                        // Récupérer les segments de la transcription
                        let segments = result.bestTranscription.segments
                        
                        // Stocker les segments originaux avec leurs horodatages
                        var rawSegments: [TranscriptionSegment] = []
                        
                        for segment in segments {
                            let text = segment.substring
                            let startTime = segment.timestamp
                            let duration = segment.duration
                            
                            let newSegment = TranscriptionSegment(
                                text: text,
                                startTime: startTime,
                                endTime: startTime + duration
                            )
                            
                            rawSegments.append(newSegment)
                        }
                        
                        // Générer les segments de phrases pour l'interface utilisateur
                        self.transcriptionSegments = self.createPhraseSegments(rawSegments)
                        
                        // Utiliser la fonction existante pour créer la transcription formatée
                        self.formattedTranscription = self.processTranscriptionSegments(rawSegments)
                        
                        // Mettre à jour le texte de transcription
                        self.transcriptionText = self.formattedTranscription
                        
                        // Si c'est le résultat final, marquer comme terminé
                        if result.isFinal {
                            self.isTranscribing = false
                        }
                    }
                }
                
                // Stocker la tâche pour annulation potentielle si nécessaire
                self.recognitionTask = task
            }
        }
    }


private func processTranscriptionSegments(_ segments: [TranscriptionSegment]) -> String {
    guard !segments.isEmpty else { return "" }
    
    var formattedText = ""
    var lastEndTime: TimeInterval = 0
    
    // Configuration des seuils de pause
    let longPauseThreshold: TimeInterval = 0.4  // Réduit de 0.7 à 0.4 seconde
    let mediumPauseThreshold: TimeInterval = 0.2  // Réduit de 0.3 à 0.2 seconde
    
    for (index, segment) in segments.enumerated() {
        let text = segment.text
        
        if index > 0 {
            // Calculer le temps entre ce segment et le précédent
            let pauseDuration = segment.startTime - lastEndTime
            
            // Si la pause est suffisamment longue, ajouter une ponctuation
            if pauseDuration > longPauseThreshold {  // Seuil réduit pour une pause significative
                // Vérifier si le dernier caractère est déjà une ponctuation
                let lastChar = formattedText.last
                
                if lastChar != "." && lastChar != "," && lastChar != "?" && lastChar != "!" {
                    // Ajouter un point et une nouvelle ligne
                    formattedText += ".\n\n"
                } else if lastChar != "\n" {
                    // Ajouter juste une nouvelle ligne
                    formattedText += "\n\n"
                }
            } else if pauseDuration > mediumPauseThreshold {  // Seuil réduit pour une pause moyenne
                // Ajouter une virgule si ce n'est pas déjà fait
                let lastChar = formattedText.last
                
                if lastChar != "," && lastChar != "." && lastChar != "?" && lastChar != "!" {
                    formattedText += ", "
                } else {
                    formattedText += " "
                }
            } else {
                // Juste un espace
                if !formattedText.hasSuffix(" ") {
                    formattedText += " "
                }
            }
        }
        
        // Ajouter le texte du segment (capitalisé si c'est après un point)
        if index == 0 || (formattedText.last == "\n" || formattedText.hasSuffix(". ")) {
            formattedText += text.prefix(1).uppercased() + text.dropFirst()
        } else {
            formattedText += text
        }
        
        lastEndTime = segment.endTime
    }
    
    // Assurer qu'il y a un point final
    if !formattedText.isEmpty && !".!?".contains(formattedText.last!) {
        formattedText += "."
    }
    
    return formattedText
}
    
    // Ajoutez cette fonction pour gérer la lecture des segments sélectionnés
    private func togglePlaySelectedSegments() {
        if isPlayingSelectedSegments {
            // Si déjà en cours de lecture, arrêter
            stopPlayingSelectedSegments()
        } else {
            // Sinon, commencer la lecture
            startPlayingSelectedSegments()
        }
        
        isPlayingSelectedSegments.toggle()
    }

// Fonction pour démarrer la lecture des segments sélectionnés
private func startPlayingSelectedSegments() {
    // Filtrer les segments actifs
    let activeSegments = transcriptionSegments.filter { $0.isActive }
    
    // S'assurer qu'il y a des segments actifs
    if activeSegments.isEmpty {
        return
    }
    
    // Réinitialiser l'index
    currentSegmentIndex = 0
    
    // Commencer par le premier segment actif
    playSegment(activeSegments[currentSegmentIndex])
    
    // Configurer un timer pour gérer le passage d'un segment à l'autre
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        
        // Vérifier si nous sommes toujours dans le segment actuel
        let activeSegments = self.transcriptionSegments.filter { $0.isActive }
        if self.currentSegmentIndex < activeSegments.count {
            let currentSegment = activeSegments[self.currentSegmentIndex]
            let currentPlayerTime = CMTimeGetSeconds(self.player.currentTime())
            
            // Si nous avons atteint la fin du segment actuel
            if currentPlayerTime >= currentSegment.endTime {
                // Passer au segment suivant
                self.currentSegmentIndex += 1
                
                // S'il y a encore des segments à lire
                if self.currentSegmentIndex < activeSegments.count {
                    self.playSegment(activeSegments[self.currentSegmentIndex])
                } else {
                    // Plus de segments à lire, arrêter la lecture
                    self.stopPlayingSelectedSegments()
                    self.isPlayingSelectedSegments = false
                }
            }
        }
    }
}

    // Fonction pour lire un segment spécifique
    private func playSegment(_ segment: TranscriptionSegment) {
        // Aller au début du segment
        let time = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: time)
        
        // Lancer la lecture
        player.play()
        isPlaying = true
        
        // Mettre à jour l'UI
        currentTime = segment.startTime
    }

    // Fonction pour arrêter la lecture des segments sélectionnés
    private func stopPlayingSelectedSegments() {
        // Arrêter le timer
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // Mettre en pause le lecteur
        player.pause()
        isPlaying = false
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



