import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Speech


// Ajout d'une structure pour stocker les segments avec horodatage
struct TranscriptionSegment: Identifiable {
    var index: Int
    var id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var duration: TimeInterval {
        return endTime - startTime
    }
    var indexFusion: Int = 0
    var isActive: Bool = true 
    var durationAdjustment: Double = 0.0 // Pour suivre l'ajustement de durée
}

// Structure pour la requête ChatGPT
struct ChatGPTRequest: Codable {
    let model: String
    let messages: [Message]
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

// Structure pour la réponse ChatGPT
struct ChatGPTResponse: Codable {
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
    
    let choices: [Choice]
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
    @State private var originalSegments: [TranscriptionSegment] = [] // Pour sauvegarder les segments originaux
    @State private var isZoomedIn: Bool = false
    @State private var isCorrectingText: Bool = false // Pour suivre l'état de la correction
    @StateObject private var chatGPTService = ChatGPTService(apiKey: APIKeys.openAI)
    @State private var audioURL: URL? = nil
    @State private var showAudioFileName: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isAudioPlaying: Bool = false
    @State private var audioVolume: Float = 0.5 // Volume par défaut à 50%


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
                            // Réinitialiser la composition vidéo pour revenir à la taille normale
                            player.currentItem?.videoComposition = nil
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
        
        Text("MONTAGE")
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(index + 1)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            Text(String(format: "%.1fs - %.1fs (Durée: %.1fs)", 
                                transcriptionSegments[index].startTime, 
                                transcriptionSegments[index].endTime,
                                transcriptionSegments[index].duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Affichage de l'ajustement de durée
                            if transcriptionSegments[index].durationAdjustment != 0 {
                                Text(String(format: "%+.1fs", transcriptionSegments[index].durationAdjustment))
                                    .font(.caption)
                                    .foregroundColor(transcriptionSegments[index].durationAdjustment > 0 ? .green : .red)
                                    .padding(.horizontal, 4)
                            }
                            
                            Spacer()
                            
                            // Boutons d'ajustement de durée
                            Button(action: {
                                adjustSegmentDuration(index: index, adjustment: -0.5)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 2)
                            
                            Button(action: {
                                adjustSegmentDuration(index: index, adjustment: 0.5)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 2)
                            
                            // Bouton de fusion existant
                            if index > 0 {
                                Button(action: {
                                    mergeWithPreviousSegment(index)
                                }) {
                                    Image(systemName: "arrow.merge")
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 4)
                            }
                            
                            // Bouton d'activation/désactivation existant
                            Button(action: {
                                transcriptionSegments[index].isActive.toggle()
                                updateFormattedTranscription()
                            }) {
                                Image(systemName: transcriptionSegments[index].isActive ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(transcriptionSegments[index].isActive ? .blue : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
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
                    // Conserver le double-tap pour la navigation
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
    
    // Modifiez la section des boutons en bas à droite
    if !transcriptionSegments.isEmpty && !isTranscribing {
        Spacer()
        
        VStack(spacing: 10) {
            // Zone d'affichage du fichier audio sélectionné avec contrôles
            if let audioURL = audioURL {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text(audioURL.lastPathComponent)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .font(.system(size: 14))
                        
                        Button(action: {
                            stopAudio()
                            self.audioURL = nil
                            showAudioFileName = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Contrôle du volume uniquement (sans bouton de lecture)
                    HStack {
                        Image(systemName: "speaker.wave.1.fill")
                            .foregroundColor(.orange)
                        
                        Slider(value: $audioVolume, in: 0...1) { editing in
                            if !editing {
                                audioPlayer?.volume = audioVolume
                            }
                        }
                        .accentColor(.orange)
                        .frame(width: 100)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }
            }

            HStack {
                // Bouton Reset (existant)
                Button(action: {
                    resetSegments()
                }) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 10)
                
                Spacer()

                // Bouton Audio
                Button(action: {
                    if let url = openAudioFileDialog() {
                        audioURL = url
                        showAudioFileName = true
                        prepareAudioPlayer(url: url)
                    }
                }) {
                    Image(systemName: audioURL == nil ? "music.note.list" : "music.note.list.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.orange)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 10)

                // Bouton Restart (existant)
                Button(action: {
                    restartPlayback()
                }) {
                    Image(systemName: "backward.end.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 10)
                
                // Bouton Play/Pause (existant)
                Button(action: {
                    togglePlaySelectedSegments()
                }) {
                    Image(systemName: isPlayingSelectedSegments ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
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
            
            // Arrêter et nettoyer l'audio
            stopAudio()
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
                        var phrase = TranscriptionSegment(
                            index: 0, text: currentPhraseText,
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
                var phrase = TranscriptionSegment(
                    index: 0,
                    text: currentPhraseText,
                    startTime: phraseStartTime,
                    endTime: phraseEndTime,
                    isActive: true
                )
                phrases.append(phrase)
            }
            
        }
                     
        for (index,phrase) in phrases.enumerated() {
            var tmpPhrase = phrase
            tmpPhrase.index = index + 1
            phrases[index] = tmpPhrase
        }
        
        return phrases
    }

    private func mergeShortSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        var mergedSegments = segments // Create a mutable copy
        var i = mergedSegments.count - 1 // On commence par la fin
        
        while i > 0 { // On s'arrête quand on arrive au premier segment
            // Si le segment actuel est court
            if mergedSegments[i].duration < 2 {
                // Fusionner avec le segment précédent
                mergedSegments[i - 1].endTime = mergedSegments[i].endTime
                mergedSegments[i - 1].text = mergedSegments[i - 1].text + " " + mergedSegments[i].text
                
                // Supprimer le segment actuel
                mergedSegments.remove(at: i)
            }
            i -= 1
        }
        
        // Mettre à jour les index
        for i in 0..<mergedSegments.count {
            mergedSegments[i].index = i + 1
        }
        
        return mergedSegments
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
                        
                        for (index, segment) in segments.enumerated() {
                            let text = segment.substring
                            let startTime = segment.timestamp
                            let duration = segment.duration
                            
                            let newSegment = TranscriptionSegment(
                                index: index,
                                text: text,
                                startTime: startTime,
                                endTime: startTime + duration
                            )
                            
                            rawSegments.append(newSegment)
                        }
                        
                        // Générer les segments de phrases pour l'interface utilisateur
                        self.transcriptionSegments = self.createPhraseSegments(rawSegments)

                        // Fusionner les segments courts
                        //self.transcriptionSegments = self.mergeShortSegments(self.transcriptionSegments)
                        
                        // Utiliser la fonction existante pour créer la transcription formatée
                        self.formattedTranscription = self.processTranscriptionSegments(rawSegments)
                        
                        // Mettre à jour le texte de transcription
                        self.transcriptionText = self.formattedTranscription
                        
                        // Sauvegarder les segments originaux
                        self.originalSegments = self.transcriptionSegments
                        
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
    let longPauseThreshold: TimeInterval = 0.7  // Réduit de 0.7 à 0.4 seconde
    let mediumPauseThreshold: TimeInterval = 0.3  // Réduit de 0.3 à 0.2 seconde
    
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
    
    // Démarrer l'audio si disponible
    if let player = audioPlayer, !player.isPlaying {
        player.play()
        isAudioPlaying = true
    }
    
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

    // Modifiez la fonction playSegment comme suit
    private func playSegment(_ segment: TranscriptionSegment) {
        // Aller au début du segment
        let time = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: time)
        
        // Réinitialiser la composition vidéo avant d'appliquer un nouvel effet
        player.currentItem?.videoComposition = nil
        
        // Vérifier la durée du segment
        let segmentDuration = segment.endTime - segment.startTime
        
        if selectedEffect == "ZOOM" {
            // Créer une composition vidéo avec animation de zoom
            let videoComposition = AVVideoComposition(asset: player.currentItem!.asset) { [isZoomedIn] request in
                let source = request.sourceImage
                
                // Calculer le facteur de zoom en fonction du temps
                let zoomDuration: Double = 0.5 // Durée de l'animation en secondes
                let maxZoom: Double = 1.3 // Réduit légèrement le zoom maximum pour éviter les bords noirs
                let currentTime = CMTimeGetSeconds(request.compositionTime) - segment.startTime
                
                var scale: Double = 1.0
                if currentTime <= zoomDuration {
                    if !isZoomedIn {
                        // Zoom in progressif
                        scale = 1.0 + (maxZoom - 1.0) * min(1.0, (currentTime / zoomDuration))
                    } else {
                        // Zoom out progressif
                        scale = maxZoom - (maxZoom - 1.0) * min(1.0, (currentTime / zoomDuration))
                    }
                } else {
                    // Maintenir le zoom final
                    scale = isZoomedIn ? 1.0 : maxZoom
                }
                
                // S'assurer que le scale reste dans des limites raisonnables
                scale = max(1.0, min(maxZoom, scale))
                
                // Appliquer la transformation
                let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
                
                // Calculer la translation pour centrer avec des limites
                let translateX = ((1.0 - scale) * source.extent.width) / 2.0
                let translateY = ((1.0 - scale) * source.extent.height) / 2.0
                
                // Limiter la translation pour éviter les bords noirs
                let maxTranslate = source.extent.width * (scale - 1.0) / 2.0
                let boundedTranslateX = max(-maxTranslate, min(maxTranslate, translateX))
                let boundedTranslateY = max(-maxTranslate, min(maxTranslate, translateY))
                
                let translateTransform = CGAffineTransform(translationX: boundedTranslateX, y: boundedTranslateY)
                
                // Combiner les transformations
                let transform = scaleTransform.concatenating(translateTransform)
                let transformedImage = source.transformed(by: transform)
                
                request.finish(with: transformedImage, context: nil)
            }
            
            player.currentItem?.videoComposition = videoComposition
            
            // Inverser l'état du zoom pour le prochain segment
            DispatchQueue.main.async {
                self.isZoomedIn.toggle()
            }
        } else if selectedEffect == "JUMP CUT" && currentSegmentIndex % 2 == 0 && segmentDuration >= 3 {
            // Code existant pour JUMP CUT
            let videoComposition = AVVideoComposition(asset: player.currentItem!.asset) { request in
                let source = request.sourceImage
                let scaleTransform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                let translateTransform = CGAffineTransform(translationX: -source.extent.width / 4, y: -source.extent.height / 4)
                let transform = scaleTransform.concatenating(translateTransform)
                let transformedImage = source.transformed(by: transform)
                request.finish(with: transformedImage, context: nil)
            }
            player.currentItem?.videoComposition = videoComposition
        }
        
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
        
        // Mettre en pause l'audio automatiquement
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isAudioPlaying = false
        }
    }
    
    // Ajoutez cette fonction dans ContentView
    private func mergeWithPreviousSegment(_ currentIndex: Int) {
        guard currentIndex > 0 && currentIndex < transcriptionSegments.count else { return }
        
        // Fusionner avec le segment précédent
        var previousSegment = transcriptionSegments[currentIndex - 1]
        let currentSegment = transcriptionSegments[currentIndex]
        
        // Mettre à jour le texte et le temps de fin du segment précédent
        previousSegment.text = previousSegment.text + " " + currentSegment.text
        previousSegment.endTime = currentSegment.endTime
        
        // Mettre à jour le segment précédent
        transcriptionSegments[currentIndex - 1] = previousSegment
        
        // Supprimer le segment actuel
        transcriptionSegments.remove(at: currentIndex)
        
        // Mettre à jour les index des segments restants
        for i in 0..<transcriptionSegments.count {
            transcriptionSegments[i].index = i + 1
        }
        
        // Mettre à jour la transcription formatée
        updateFormattedTranscription()
    }

    // Ajoutez ces nouvelles fonctions dans ContentView
    private func resetSegments() {
        transcriptionSegments = originalSegments.map { segment in
            var newSegment = segment
            newSegment.isActive = true
            newSegment.durationAdjustment = 0.0 // Réinitialiser l'ajustement de durée
            return newSegment
        }
        updateFormattedTranscription()
    }

    private func restartPlayback() {
        // Arrêter la lecture en cours si elle est active
        if isPlayingSelectedSegments {
            stopPlayingSelectedSegments()
        }
        
        // Réinitialiser l'index de lecture
        currentSegmentIndex = 0
        
        // Réinitialiser l'audio à sa position de départ si nécessaire
        if let player = audioPlayer {
            player.currentTime = 0
        }
        
        // Démarrer la lecture depuis le début
        isPlayingSelectedSegments = true
        startPlayingSelectedSegments()
    }

    // Ajoutez cette nouvelle fonction à ContentView
    private func adjustSegmentDuration(index: Int, adjustment: Double) {
        guard index < transcriptionSegments.count else { return }
        
        // Mettre à jour l'ajustement de durée
        transcriptionSegments[index].durationAdjustment += adjustment
        
        // Ajuster la fin du segment actuel
        transcriptionSegments[index].endTime += adjustment
        
        // Si ce n'est pas le dernier segment, ajuster le début du segment suivant
        if index < transcriptionSegments.count - 1 {
            transcriptionSegments[index + 1].startTime += adjustment
        }
        
        // Mettre à jour la transcription formatée
        updateFormattedTranscription()
    }

    // Ajoutez cette fonction pour corriger le texte avec ChatGPT
    private func correctTranscriptionWithChatGPT() async {
        guard !transcriptionText.isEmpty else { return }
        
        isCorrectingText = true
        
        do {
            let correctedText = try await chatGPTService.correctText(transcriptionText)
            
            DispatchQueue.main.async {
                self.transcriptionText = correctedText
                self.updateSegmentsWithCorrectedText(correctedText)
                self.isCorrectingText = false
            }
        } catch {
            DispatchQueue.main.async {
                // Gérer les erreurs ici
                print("Erreur de correction : \(error)")
                self.isCorrectingText = false
            }
        }
    }

    // Ajoutez cette fonction pour mettre à jour les segments avec le texte corrigé
    private func updateSegmentsWithCorrectedText(_ correctedText: String) {
        // Diviser le texte corrigé en phrases
        let phrases = correctedText.components(separatedBy: "\n\n")
        
        var currentIndex = 0
        for phrase in phrases {
            if currentIndex < transcriptionSegments.count {
                transcriptionSegments[currentIndex].text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                currentIndex += 1
            }
        }
        
        // Mettre à jour la transcription formatée
        updateFormattedTranscription()
    }

    // Ajoutez cette fonction pour gérer le chargement de fichiers audio
    private func openAudioFileDialog() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.wav, UTType.mp3, UTType.audio]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false

        if openPanel.runModal() == .OK {
            return openPanel.url
        }
        return nil
    }

    // Ajoutez ces nouvelles fonctions pour gérer la lecture audio
    
    private func prepareAudioPlayer(url: URL) {
        do {
            // Arrêter l'audio précédent s'il existe
            stopAudio()
            
            // Créer un nouveau lecteur audio
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = audioVolume
            // Ne pas démarrer la lecture automatiquement
        } catch {
            print("Erreur lors de la préparation du lecteur audio: \(error.localizedDescription)")
        }
    }
    
    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
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



