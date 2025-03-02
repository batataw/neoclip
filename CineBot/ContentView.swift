import AVKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

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
    var durationAdjustment: Double = 0.0  // Pour suivre l'ajustement de durée
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
    @State private var selectedEffect: String = "SANS"  // Default effect
    @State private var originalSegments: [TranscriptionSegment] = []  // Pour sauvegarder les segments originaux
    @State private var isZoomedIn: Bool = false
    @State private var isCorrectingText: Bool = false  // Pour suivre l'état de la correction
    @StateObject private var chatGPTService = ChatGPTService(apiKey: APIKeys.openAI)
    @State private var audioURL: URL? = nil
    @State private var showAudioFileName: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isAudioPlaying: Bool = false
    @State private var audioVolume: Float = 0.5  // Volume par défaut à 50%
    @State private var currentScaleFactor: CGFloat = 1.0  // Pour suivre le facteur d'échelle actuel
    @State private var randomGenerator = SystemRandomNumberGenerator()
    @State private var videoTitle: String = ""  // Variable d'état pour le titre
    @State private var videoDescription: String = ""  // Variable d'état pour la description
    @State private var videoHashtags: String = ""  // Variable d'état pour les hashtags
    @State private var showCopyNotification: Bool = false
    @State private var isGeneratingContent: Bool = false
    @State private var showTitleOverlay: Bool = false
    @State private var titleBackgroundColor: Color = .blue
    @State private var titleFontSize: Double = 24
    @State private var titleBorderWidth: Double = 2
    @State private var titleDuration: String = "5s"  // Options: "5s", "10s", "Tout"
    @State private var titleFontName: String = "System" // Police par défaut

    var body: some View {
        mainContentView
            .onDisappear {
                cleanupResources()
            }
            .onAppear {
                addPeriodicTimeObserver()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("No Video Loaded"),
                    message: Text("Please load a video before starting transcription."),
                    dismissButton: .default(Text("OK")))
            }
    }

    // Break up the body into smaller components
    private var mainContentView: some View {
        HStack(alignment: .top) {
            videoPlayerSection
                .frame(maxWidth: .infinity)

            transcriptionSection
                .frame(maxWidth: .infinity)

            titleAndDescriptionSection
                .frame(maxWidth: .infinity)  // Limiter la largeur pour un bon alignement
        }
    }

    // Nouvelle section pour le titre et la description
    private var titleAndDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleDescriptionHeader

            VStack(alignment: .leading, spacing: 5) {
                Text("Titre")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))  // Fond gris doux
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)  // Bordure gris foncé
                        )

                    TextEditor(text: $videoTitle)
                        .font(.system(size: 14))  // Définir la police à 14
                        .padding(4)  // Petit padding interne
                        .scrollContentBackground(.hidden)  // Masque le fond par défaut
                        .background(Color.gray.opacity(0.2))  // Applique un fond similaire
                        .cornerRadius(6)  // Légèrement plus petit que le conteneur
                }
                .frame(height: 40)  // Hauteur fixe pour le titre
                .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)
                .padding(.horizontal)
            }

            // Ajouter les options de superposition du titre
            titleOverlayOptionsSection

            VStack(alignment: .leading, spacing: 5) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))  // Fond gris doux
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)  // Bordure gris foncé
                        )

                    TextEditor(text: $videoDescription)
                        .font(.system(size: 14))  // Définir la police à 14
                        .padding(4)  // Petit padding interne
                        .scrollContentBackground(.hidden)  // Masque le fond par défaut
                        .background(Color.gray.opacity(0.2))  // Applique un fond similaire à TextField
                        .cornerRadius(6)  // Légèrement plus petit que le conteneur
                }
                .frame(height: 140)  // Hauteur appliquée au ZStack
                .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Hashtags")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.leading)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))  // Fond gris doux
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)  // Bordure gris foncé
                        )

                    TextEditor(text: $videoHashtags)
                        .font(.system(size: 14))  // Définir la police à 14
                        .padding(4)  // Petit padding interne
                        .scrollContentBackground(.hidden)  // Masque le fond par défaut
                        .background(Color.gray.opacity(0.2))  // Applique un fond similaire à TextField
                        .cornerRadius(6)  // Légèrement plus petit que le conteneur
                }
                .frame(height: 40)  // Hauteur appliquée au ZStack
                .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)
                .padding(.horizontal)
            }

            Spacer()

            // N'afficher les boutons que si une transcription est disponible
            if !transcriptionText.isEmpty {
                titleDescriptionButtonsSection
            }
        }
        .padding(.bottom)  // Supprimé .padding(.vertical) pour enlever la marge du haut
        .background(Color.gray.opacity(0.1))
    }

    // Nouvelle section pour les options de superposition du titre
    private var titleOverlayOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Options de superposition du titre")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.leading)
            
            HStack {
                Toggle("Afficher le titre", isOn: $showTitleOverlay)
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                Spacer()
            }
            .padding(.horizontal)
            
            if showTitleOverlay {
                // Première ligne d'options
                HStack(spacing: 15) {
                    VStack(alignment: .leading) {
                        Text("Couleur")
                            .font(.caption)
                        ColorPicker("", selection: $titleBackgroundColor)
                            .labelsHidden()
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Taille")
                            .font(.caption)
                        Slider(value: $titleFontSize, in: 16...36, step: 1)
                            .frame(width: 100)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Bordure")
                            .font(.caption)
                        Slider(value: $titleBorderWidth, in: 0...10, step: 0.5)  // Augmenté à 10
                            .frame(width: 100)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Deuxième ligne d'options
                HStack(spacing: 15) {
                    VStack(alignment: .leading) {
                        Text("Durée")
                            .font(.caption)
                        Picker("", selection: $titleDuration) {
                            Text("5 secondes").tag("5s")
                            Text("10 secondes").tag("10s")
                            Text("Tout le clip").tag("Tout")
                        }
                        .frame(width: 120)
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Police")
                            .font(.caption)
                        Picker("", selection: $titleFontName) {
                            Text("System").tag("System")
                            Text("Helvetica").tag("Helvetica")
                            Text("Arial").tag("Arial")
                            Text("Times New Roman").tag("Times New Roman")
                            Text("Avenir").tag("Avenir")
                            Text("Georgia").tag("Georgia")
                        }
                        .frame(width: 150)
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // Ajout de la nouvelle section de boutons pour titre et description
    private var titleDescriptionButtonsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Spacer()

                // Bouton ChatGPT - désactivé si pas de transcription ou si génération en cours
                VStack {
                    ZStack {
                        Button(action: {
                            Task {
                                await generateTitleAndDescription()
                            }
                        }) {
                            Image(systemName: "book.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .foregroundColor(
                                    transcriptionText.isEmpty || isGeneratingContent
                                        ? .gray : .orange)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(transcriptionText.isEmpty || isGeneratingContent)

                        // Indicateur de chargement
                        if isGeneratingContent {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(1.5)
                        }
                    }

                    Text("Remplir")
                        .font(.caption)
                        .foregroundColor(
                            transcriptionText.isEmpty || isGeneratingContent ? .gray : .orange)
                }

                // Bouton Copier avec notification - désactivé si pas de contenu
                VStack {
                    ZStack {
                        Button(action: {
                            copyToClipboard()
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .foregroundColor(hasContentToCopy ? .green : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!hasContentToCopy)

                        // Notification de copie
                        if showCopyNotification {
                            Text("Copié !")
                                .font(.caption)
                                .padding(6)
                                .background(Color.white.opacity(0.9))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: -30)
                        }
                    }

                    Text("Copier")
                        .font(.caption)
                        .foregroundColor(hasContentToCopy ? .green : .gray)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.2))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
        .overlay(
            // HUD global pour l'ensemble de la section
            Group {
                if isGeneratingContent {
                    ZStack {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)

                        VStack(spacing: 15) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(2.0)

                            Text("Génération en cours...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(25)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                }
            }
        )
    }

    // Propriété calculée pour vérifier s'il y a du contenu à copier
    private var hasContentToCopy: Bool {
        return !videoTitle.isEmpty || !videoDescription.isEmpty || !videoHashtags.isEmpty
    }

    // Bandeau violet pour la section titre et description
    private var titleDescriptionHeader: some View {
        ZStack {
            Rectangle()
                .fill(Color.purple.opacity(0.2))
                .frame(height: 60)

            Text("TITRE & DESCRIPTION")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.purple)
        }
    }

    // Video player section
    private var videoPlayerSection: some View {
        VStack {
            videoHeader
            videoPlayer
            videoProgressBar
            videoControlButtons
        }
        .frame(maxWidth: .infinity)
    }

    // Video header
    private var videoHeader: some View {
        ZStack {
            Rectangle()
                .fill(Color.blue.opacity(0.2))
                .frame(height: 60)

            Text("LECTEUR VIDÉO")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.blue)
        }
    }

    // Video player
    private var videoPlayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                
                // Superposition du titre si activée et selon la durée choisie
                if showTitleOverlay && !videoTitle.isEmpty && shouldShowTitleOverlay {
                    titleOverlayView(containerWidth: geometry.size.width)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding()
    }

    // Propriété calculée pour déterminer si le titre doit être affiché
    private var shouldShowTitleOverlay: Bool {
        switch titleDuration {
        case "5s":
            return currentTime < 5.0
        case "10s":
            return currentTime < 10.0
        case "Tout":
            return true
        default:
            return currentTime < 5.0
        }
    }

    // Vue du titre superposé avec la largeur du conteneur
    private func titleOverlayView(containerWidth: CGFloat) -> some View {
        // Calculer la largeur réelle de la vidéo
        let videoWidth = min(containerWidth, containerWidth / (16/9))
        // Calculer la largeur maximale du titre (80% de la largeur de la vidéo)
        let titleMaxWidth = videoWidth * 0.8
        
        return VStack {
            Text(videoTitle)
                .font(Font.custom(titleFontName == "System" ? ".AppleSystemUIFont" : titleFontName, size: CGFloat(titleFontSize)))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: titleMaxWidth)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(titleBackgroundColor.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white, lineWidth: CGFloat(titleBorderWidth))
                        )
                )
                .padding(.top, 20) // Espace en haut pour ne pas être trop proche du bord supérieur
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: shouldShowTitleOverlay)
    }

    // Video progress bar
    private var videoProgressBar: some View {
        Slider(
            value: $currentTime, in: 0...videoDuration,
            onEditingChanged: { isEditing in
                if !isEditing {
                    let newTime = CMTime(seconds: currentTime, preferredTimescale: 600)
                    player.seek(to: newTime)
                }
            }
        )
        .padding()
    }

    // Video control buttons
    private var videoControlButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                openFileButton
                playPauseButton
                stopButton
                Spacer()
                transcriptionButton
            }
            .padding()
            .background(Color.blue.opacity(0.2))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
    }

    // Control buttons section
    private var controlButtonsSection: some View {
        VStack(spacing: 10) {
            audioFileSection

            HStack {
                resetButton
                Spacer()
                audioButton
                restartButton
                playPauseSegmentsButton
            }
            .padding()
            .background(Color.green.opacity(0.2))  // Fond vert pour correspondre au thème de la section Montage
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
    }

    private var openFileButton: some View {
        VStack {
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

            Text("Ouvrir")
                .font(.caption)
                .foregroundColor(.yellow)
        }
    }

    private var playPauseButton: some View {
        VStack {
            Button(action: {
                if asset == nil {
                    showAlert = true
                } else {
                    if isPlaying {
                        player.pause()
                    } else {
                        // Réinitialiser la composition vidéo pour revenir à la taille normale
                        player.currentItem?.videoComposition = nil
                        player.play()
                    }
                    isPlaying.toggle()
                }
            }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())

            Text(isPlaying ? "Pause" : "Lire")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }

    private var stopButton: some View {
        VStack {
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

            Text("Stop")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private var transcriptionButton: some View {
        VStack {
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

            Text("Transcrire")
                .font(.caption)
                .foregroundColor(.green)
        }
    }

    // Transcription section
    private var transcriptionSection: some View {
        VStack {
            transcriptionHeader
            effectSelector
            transcriptionContent
            Spacer()
            if !transcriptionSegments.isEmpty && !isTranscribing {
                Spacer()
                controlButtonsSection
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
    }

    // Transcription header
    private var transcriptionHeader: some View {
        ZStack {
            Rectangle()
                .fill(Color.green.opacity(0.2))
                .frame(height: 60)

            Text("MONTAGE")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.green)
        }
    }

    // Effect selector
    private var effectSelector: some View {
        Picker("Effet", selection: $selectedEffect) {
            Text("SANS").tag("SANS")
            Text("JUMP CUT").tag("JUMP CUT")
            Text("ZOOM").tag("ZOOM")
            Text("MIX").tag("MIX")
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
        .background(Color.green.opacity(0.2))
        .cornerRadius(8)
        .shadow(color: .gray, radius: 3, x: 0, y: 2)
        .padding(.horizontal)
    }

    // Transcription content
    private var transcriptionContent: some View {
        Group {
            if isTranscribing {
                transcribingView
            } else if !transcriptionSegments.isEmpty {
                segmentsListView
            } else if !transcriptionText.isEmpty {
                formattedTextView
            } else {
                emptyTranscriptionView
            }
        }
    }

    private var transcribingView: some View {
        ScrollView {
            VStack {
                ProgressView()
                    .padding()
                Text(transcriptionText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(5)
            }
        }
        .padding()
    }

    private var formattedTextView: some View {
        ScrollView {
            Text(transcriptionText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(5)
        }
        .padding()
    }

    private var emptyTranscriptionView: some View {
        Text(
            "Pas encore de transcription disponible. Cliquez sur le bouton de transcription pour commencer."
        )
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segmentsListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(transcriptionSegments.indices, id: \.self) { index in
                    segmentView(for: index)
                }
            }
            .padding()
        }
    }

    private func segmentView(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            segmentHeader(for: index)
            segmentText(for: index)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            transcriptionSegments[index].isActive
                ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)
        )
        .cornerRadius(8)
        .onTapGesture(count: 2) {
            navigateToSegment(transcriptionSegments[index])
        }
    }

    private func segmentHeader(for index: Int) -> some View {
        HStack {
            Text("#\(index + 1)")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)

            // Ajout du nombre de mots et de caractères
            Text(
                String(
                    format: "%d mots, %d car. | %.1fs - %.1fs (Durée: %.1fs)",
                    transcriptionSegments[index].text.split(separator: " ").count,
                    transcriptionSegments[index].text.count,
                    transcriptionSegments[index].startTime,
                    transcriptionSegments[index].endTime,
                    transcriptionSegments[index].duration)
            )
            .font(.caption)
            .foregroundColor(.secondary)

            // Affichage de l'ajustement de durée
            if transcriptionSegments[index].durationAdjustment != 0 {
                Text(String(format: "%+.1fs", transcriptionSegments[index].durationAdjustment))
                    .font(.caption)
                    .foregroundColor(
                        transcriptionSegments[index].durationAdjustment > 0 ? .green : .red
                    )
                    .padding(.horizontal, 4)
            }

            Spacer()

            segmentControlButtons(for: index)
        }
    }

    private func segmentControlButtons(for index: Int) -> some View {
        HStack(spacing: 2) {
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
                Image(
                    systemName: transcriptionSegments[index].isActive
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundColor(transcriptionSegments[index].isActive ? .blue : .gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func segmentText(for index: Int) -> some View {
        Text(transcriptionSegments[index].text)
            .font(.body)
            .foregroundColor(transcriptionSegments[index].isActive ? .primary : .gray)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var audioFileSection: some View {
        Group {
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

                    // Contrôle du volume uniquement
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
            } else {
                EmptyView()
            }
        }
    }

    private var resetButton: some View {
        VStack {
            Button(action: {
                resetSegments()
            }) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())

            Text("Réinitialiser")
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 10)
    }

    private var audioButton: some View {
        VStack {
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

            Text("Audio")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 10)
    }

    private var restartButton: some View {
        VStack {
            Button(action: {
                restartPlayback()
            }) {
                Image(systemName: "backward.end.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())

            Text("Redémarrer")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 10)
    }

    private var playPauseSegmentsButton: some View {
        VStack {
            Button(action: {
                togglePlaySelectedSegments()
            }) {
                Image(
                    systemName: isPlayingSelectedSegments ? "pause.circle.fill" : "play.circle.fill"
                )
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())

            Text(isPlayingSelectedSegments ? "Pause" : "Lire")
                .font(.caption)
                .foregroundColor(.green)
        }
    }

    // Clean up resources
    private func cleanupResources() {
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

    // Charger la vidéo
    private func loadVideo(url: URL) {
        let videoAsset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: videoAsset)
        player.replaceCurrentItem(with: playerItem)
        asset = videoAsset
        videoURL = url

        // Réinitialiser les données de transcription
        transcriptionText = ""
        transcriptionSegments = []
        formattedTranscription = ""
        originalSegments = []

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
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "audio_for_transcription.m4a")

        // Remove any existing file at that URL
        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                try FileManager.default.removeItem(at: audioURL)
            } catch {
                DispatchQueue.main.async {
                    self.transcriptionText =
                        "Error removing temporary file: \(error.localizedDescription)"
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
        guard
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
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
                    self.transcriptionText =
                        "Failed to load asset tracks: \(error?.localizedDescription ?? "Unknown error")"
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
                guard
                    let exportSession = AVAssetExportSession(
                        asset: composition,
                        presetName: AVAssetExportPresetAppleM4A)
                else {
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
                            self.transcriptionText =
                                "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"
                            self.isTranscribing = false
                        }
                    case .cancelled:
                        DispatchQueue.main.async {
                            self.transcriptionText = "Export cancelled."
                            self.isTranscribing = false
                        }
                    default:
                        DispatchQueue.main.async {
                            self.transcriptionText =
                                "Export ended with status: \(exportSession.status.rawValue)"
                            self.isTranscribing = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.transcriptionText =
                        "Error setting up audio export: \(error.localizedDescription)"
                    self.isTranscribing = false
                }
            }
        }
    }

    // Ajoutez cette fonction pour créer des segments de phrases à partir des segments originaux
    private func createPhraseSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment]
    {
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
                let pauseDuration = segment.startTime - segments[index - 1].endTime

                // Si c'est une longue pause, on termine la phrase actuelle
                if pauseDuration > longPauseThreshold {
                    // Créer une nouvelle phrase avec le texte accumulé
                    if !currentPhraseText.isEmpty {
                        var phrase = TranscriptionSegment(
                            index: 0, text: currentPhraseText,
                            startTime: phraseStartTime,
                            endTime: segments[index - 1].endTime
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

        for (index, phrase) in phrases.enumerated() {
            var tmpPhrase = phrase
            tmpPhrase.index = index + 1
            phrases[index] = tmpPhrase
        }

        return phrases
    }

    private func mergeShortSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        var mergedSegments = segments  // Create a mutable copy
        var i = mergedSegments.count - 1  // On commence par la fin

        while i > 0 {  // On s'arrête quand on arrive au premier segment
            // Si le segment actuel est court
            if mergedSegments[i].duration < 2 {
                // Fusionner avec le segment précédent
                mergedSegments[i - 1].endTime = mergedSegments[i].endTime
                mergedSegments[i - 1].text =
                    mergedSegments[i - 1].text + " " + mergedSegments[i].text

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
                    self.transcriptionText =
                        "Reconnaissance vocale non autorisée: \(status.rawValue)"
                    self.isTranscribing = false
                    return
                }

                // Créer le recognizer avec la locale française
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
                else {
                    self.transcriptionText =
                        "Reconnaissance vocale non disponible pour le français."
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
                            self.transcriptionText =
                                "Erreur de reconnaissance: \(error.localizedDescription)"
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

        let longPauseThreshold: TimeInterval = 0.7
        let mediumPauseThreshold: TimeInterval = 0.3

        for (index, segment) in segments.enumerated() {
            let text = segment.text
            var newText = text

            if index > 0 {
                let pauseDuration = segment.startTime - lastEndTime

                if pauseDuration > longPauseThreshold {
                    if !formattedText.hasSuffix(".") && !formattedText.hasSuffix("!")
                        && !formattedText.hasSuffix("?") && !formattedText.hasSuffix("\n")
                    {
                        formattedText += "."
                    }

                    formattedText += "\n\n"
                } else if pauseDuration > mediumPauseThreshold {
                    if !formattedText.hasSuffix(",") && !formattedText.hasSuffix(".")
                        && !formattedText.hasSuffix("!") && !formattedText.hasSuffix("?")
                    {
                        formattedText += ","
                    }
                    formattedText += " "
                } else {
                    if !formattedText.hasSuffix(" ") {
                        formattedText += " "
                    }
                }
            }

            // Ajouter le texte capitalisé si c'est le début d'une phrase
            if index == 0 || formattedText.hasSuffix("\n\n") {
                newText = text.prefix(1).uppercased() + text.dropFirst()
            }

            formattedText += newText
            lastEndTime = segment.endTime
        }

        // Assurer une terminaison correcte
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
            applyZoomEffect(segment: segment)
        } else if selectedEffect == "JUMP CUT" && currentSegmentIndex % 2 == 0
            && segmentDuration >= 3
        {
            applyJumpCutEffect()
        } else if selectedEffect == "MIX" {
            // Pour l'effet MIX, on alterne entre différents effets de manière aléatoire
            if isZoomedIn {
                // Si on est en plan serré, on passe à un plan large
                // Choisir aléatoirement entre revenir au plan normal ou appliquer un autre effet de dézoom
                let randomChoice = Int.random(in: 0...1, using: &randomGenerator)

                if randomChoice == 0 {
                    // Revenir au plan normal (sans effet)
                    player.currentItem?.videoComposition = nil
                    currentScaleFactor = 1.0
                    isZoomedIn = false
                } else {
                    // Appliquer un effet de dézoom personnalisé (si la durée est suffisante)
                    if segmentDuration >= 2 {
                        applyCustomDeZoomEffect(segment: segment)
                    } else {
                        // Si le segment est trop court, revenir au plan normal
                        player.currentItem?.videoComposition = nil
                        currentScaleFactor = 1.0
                        isZoomedIn = false
                    }
                }
            } else {
                // Si on est en plan large, on passe à un plan serré
                // Choisir aléatoirement entre zoom et jump cut
                let randomChoice = Int.random(in: 0...1, using: &randomGenerator)

                if randomChoice == 0 {
                    applyZoomEffect(segment: segment)
                } else {
                    applyJumpCutEffect()
                }
            }
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
            newSegment.durationAdjustment = 0.0  // Réinitialiser l'ajustement de durée
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

    // Ajoutez cette fonction pour mettre à jour les segments avec le texte corrigé
    private func updateSegmentsWithCorrectedText(_ correctedText: String) {
        // Diviser le texte corrigé en phrases
        let phrases = correctedText.components(separatedBy: "\n\n")

        var currentIndex = 0
        for phrase in phrases {
            if currentIndex < transcriptionSegments.count {
                transcriptionSegments[currentIndex].text = phrase.trimmingCharacters(
                    in: .whitespacesAndNewlines)
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

    // Ajoutez ces nouvelles fonctions pour séparer la logique des effets
    private func applyZoomEffect(segment: TranscriptionSegment) {
        // Créer une composition vidéo avec animation de zoom
        let videoComposition = AVVideoComposition(asset: player.currentItem!.asset) {
            [isZoomedIn] request in
            let source = request.sourceImage

            // Calculer le facteur de zoom en fonction du temps
            let zoomDuration: Double = 0.5  // Durée de l'animation en secondes
            let maxZoom: Double = 1.3  // Zoom maximum pour éviter les bords noirs
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

            let translateTransform = CGAffineTransform(
                translationX: boundedTranslateX, y: boundedTranslateY)

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
    }

    private func applyJumpCutEffect(zoomOut: Bool = false) {
        let videoComposition = AVVideoComposition(asset: player.currentItem!.asset) { request in
            let source = request.sourceImage

            // Utiliser un facteur d'échelle fixe pour le zoom in
            let scaleFactor: CGFloat = 1.5

            // Calculer les transformations
            let scaleTransform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)

            // Pour le zoom in, on utilise une translation négative fixe
            let translateX = -source.extent.width / 4
            let translateY = -source.extent.height / 4

            let translateTransform = CGAffineTransform(translationX: translateX, y: translateY)
            let transform = scaleTransform.concatenating(translateTransform)
            let transformedImage = source.transformed(by: transform)

            request.finish(with: transformedImage, context: nil)
        }

        player.currentItem?.videoComposition = videoComposition

        // Mettre à jour l'état du zoom et le facteur d'échelle actuel
        DispatchQueue.main.async {
            self.isZoomedIn = true
            self.currentScaleFactor = 1.5
        }
    }

    // Ajoutez cette nouvelle fonction pour un effet de dézoom personnalisé
    private func applyCustomDeZoomEffect(segment: TranscriptionSegment) {
        // Créer une composition vidéo avec animation de dézoom
        let videoComposition = AVVideoComposition(asset: player.currentItem!.asset) { request in
            let source = request.sourceImage

            // Calculer le facteur de zoom en fonction du temps
            let zoomDuration: Double = 0.5  // Durée de l'animation en secondes
            let startZoom: Double = 1.3  // Commencer avec un zoom
            let endZoom: Double = 1.0  // Terminer sans zoom
            let currentTime = CMTimeGetSeconds(request.compositionTime) - segment.startTime

            // Calculer le facteur de zoom actuel
            var scale: Double = startZoom
            if currentTime <= zoomDuration {
                // Dézoom progressif
                scale = startZoom - (startZoom - endZoom) * min(1.0, (currentTime / zoomDuration))
            } else {
                // Maintenir le zoom final
                scale = endZoom
            }

            // Appliquer la transformation
            let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

            // Pour le dézoom, on utilise une translation qui maintient l'image centrée
            let translateX = ((1.0 - scale) * source.extent.width) / 2.0
            let translateY = ((1.0 - scale) * source.extent.height) / 2.0

            let translateTransform = CGAffineTransform(translationX: translateX, y: translateY)
            let transform = scaleTransform.concatenating(translateTransform)
            let transformedImage = source.transformed(by: transform)

            request.finish(with: transformedImage, context: nil)
        }

        player.currentItem?.videoComposition = videoComposition

        // Mettre à jour l'état du zoom
        DispatchQueue.main.async {
            self.isZoomedIn = false
            self.currentScaleFactor = 1.0
        }
    }

    // Ajout des nouvelles fonctions pour les boutons

    // Fonction pour générer le titre et la description avec ChatGPT
    private func generateTitleAndDescription() async {
        guard !transcriptionText.isEmpty else { return }

        // Afficher l'indicateur de chargement
        DispatchQueue.main.async {
            self.isGeneratingContent = true
        }

        do {
            // Créer un prompt pour ChatGPT
            let prompt = """
                Voici la transcription d'une vidéo:

                \(transcriptionText)

                Génère un titre accrocheur, une description engageante et des hashtags pertinents pour cette vidéo.
                Format:
                TITRE: [titre accrocheur]
                DESCRIPTION: [description engageante de 2-3 phrases]
                HASHTAGS: [5-7 hashtags pertinents]
                """

            // Appeler ChatGPT
            let response = try await chatGPTService.getResponse(for: prompt)

            // Traiter la réponse
            DispatchQueue.main.async {
                // Extraire le titre, la description et les hashtags de la réponse
                let lines = response.components(separatedBy: "\n")

                for line in lines {
                    if line.starts(with: "TITRE:") {
                        self.videoTitle = line.replacingOccurrences(of: "TITRE:", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if line.starts(with: "DESCRIPTION:") {
                        self.videoDescription = line.replacingOccurrences(
                            of: "DESCRIPTION:", with: ""
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if line.starts(with: "HASHTAGS:") {
                        self.videoHashtags = line.replacingOccurrences(of: "HASHTAGS:", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                // Masquer l'indicateur de chargement
                self.isGeneratingContent = false
            }
        } catch {
            // En cas d'erreur, masquer l'indicateur de chargement
            DispatchQueue.main.async {
                self.isGeneratingContent = false
                print(
                    "Erreur lors de la génération du titre et de la description: \(error.localizedDescription)"
                )
            }
        }
    }

    // Fonction pour copier dans le presse-papiers
    private func copyToClipboard() {
        let combinedText = """
            \(videoTitle)
            \(videoDescription)
            \(videoHashtags)
            """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(combinedText, forType: .string)

        // Afficher la notification
        withAnimation {
            showCopyNotification = true
        }

        // Masquer la notification après 2 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyNotification = false
            }
        }
    }

    // Fonction pour effacer le titre et la description
    private func clearTitleAndDescription() {
        videoTitle = ""
        videoDescription = ""
        videoHashtags = ""
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
