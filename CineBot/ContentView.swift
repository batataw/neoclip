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
    @State private var isExportingVideo: Bool = false // Variable pour suivre l'état de l'export
    @State private var exportProgress: Float = 0.0 // Variable pour suivre la progression de l'export
    @State private var alertType: AlertType? = nil // Type d'alerte à afficher
    @State private var showExportSuccessNotification: Bool = false // Pour afficher une notification de succès

    // Enum pour gérer les différents types d'alertes
    enum AlertType: Identifiable {
        case noVideo
        case exportCompleted(message: String)
        
        var id: Int {
            switch self {
            case .noVideo:
                return 0
            case .exportCompleted:
                return 1
            }
        }
    }

    var body: some View {
        mainContentView
            .onDisappear {
                cleanupResources()
            }
            .onAppear {
                addPeriodicTimeObserver()
            }
            .alert(item: $alertType) { type in
                switch type {
                case .noVideo:
                    return Alert(
                        title: Text("Aucune vidéo chargée"),
                        message: Text("Veuillez charger une vidéo avant de commencer la transcription."),
                        dismissButton: .default(Text("OK")))
                case .exportCompleted(let message):
                    return Alert(
                        title: Text("Export Vidéo"),
                        message: Text(message),
                        dismissButton: .default(Text("OK")))
                }
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
            ZStack(alignment: .center) {
                // Conteneur pour la vidéo avec ratio 9/16
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .overlay(
                        // Superposition du titre si activée et selon la durée choisie
                        Group {
                            if showTitleOverlay && !videoTitle.isEmpty && shouldShowTitleOverlay {
                                GeometryReader { overlayGeometry in
                                    // Calculer la taille réelle de la vidéo (en respectant le ratio 9/16)
                                    let videoHeight = overlayGeometry.size.width * (16/9)
                                    
                                    titleOverlayView(containerWidth: overlayGeometry.size.width)
                                        .frame(width: overlayGeometry.size.width)
                                        .position(
                                            x: overlayGeometry.size.width / 2,
                                            y: videoHeight * 0.15 // Positionner à 15% du haut
                                        )
                                }
                                .aspectRatio(9/16, contentMode: .fit)
                                .allowsHitTesting(false) // Pour que les interactions passent à travers
                            }
                        }
                    )
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
        // Calculer la largeur réelle de la vidéo (en respectant le ratio 9/16)
        let videoWidth = min(containerWidth, containerWidth)
        
        // Calculer le facteur d'échelle basé sur la largeur du conteneur
        // Utiliser une largeur de référence de 500 points
        let scaleFactor = max(0.5, min(1.2, videoWidth / 500))
        
        // Augmenter le facteur d'échelle de 20%
        let enhancedScaleFactor = scaleFactor * 1.2
        
        // Calculer la largeur maximale du titre (70% de la largeur du conteneur pour un cadre plus grand)
        let titleMaxWidth = videoWidth * 0.7
        
        // Calculer la taille de police responsive avec un minimum et un maximum
        let baseFontSize = CGFloat(titleFontSize)
        let responsiveFontSize = max(16, min(baseFontSize * 1.8, baseFontSize * enhancedScaleFactor))
        
        // Calculer l'épaisseur de bordure responsive (avec un minimum pour assurer la visibilité)
        let responsiveBorderWidth = max(1, min(6, CGFloat(titleBorderWidth) * enhancedScaleFactor))
        
        return Text(videoTitle)
            .font(Font.custom(titleFontName == "System" ? ".AppleSystemUIFont" : titleFontName, size: responsiveFontSize))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.7) // Permet à la police de réduire légèrement si nécessaire
            .padding(.horizontal, max(10, 14 * enhancedScaleFactor))
            .padding(.vertical, max(8, 10 * enhancedScaleFactor))
            .frame(maxWidth: titleMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: max(6, 10 * enhancedScaleFactor))
                    .fill(titleBackgroundColor.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: max(6, 10 * enhancedScaleFactor))
                            .stroke(Color.white, lineWidth: responsiveBorderWidth)
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: max(2, 4 * enhancedScaleFactor), x: 0, y: max(1, 2 * enhancedScaleFactor))
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
                exportVideoButton
            }
            .padding()
            .background(Color.green.opacity(0.2))  // Fond vert pour correspondre au thème de la section Montage
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .overlay(
            // Overlay pour afficher la progression de l'export
            Group {
                if isExportingVideo {
                    ZStack {
                        Color.black.opacity(0.7)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 15) {
                            Text("Export en cours...")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            ProgressView(value: exportProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .frame(width: 200)
                            
                            Text("\(Int(exportProgress * 100))%")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(25)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                }
                
                // Notification de succès d'export
                if showExportSuccessNotification {
                    VStack {
                        Spacer()
                        
                        HStack {
                            Spacer()
                            
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(.green)
                                
                                Text("Export réussi !")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(20)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(15)
                            .shadow(radius: 10)
                            .padding(.trailing, 30)
                            .padding(.bottom, 30)
                            .onAppear {
                                // Masquer la notification après 3 secondes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        showExportSuccessNotification = false
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: showExportSuccessNotification)
                }
            }
        )
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
                    alertType = .noVideo
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
                    alertType = .noVideo
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

            // Ajout du nombre de mots et de caractères avec coloration de la durée
            let duration = transcriptionSegments[index].duration
            let durationColor: Color = duration < 1.0 ? .red : (duration > 10.0 ? .orange : .secondary)
            
            Text(
                String(
                    format: "%d mots, %d car. | %.1fs - %.1fs ",
                    transcriptionSegments[index].text.split(separator: " ").count,
                    transcriptionSegments[index].text.count,
                    transcriptionSegments[index].startTime,
                    transcriptionSegments[index].endTime)
            )
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Affichage de la durée avec coloration conditionnelle
            Text(String(format: "(Durée: %.1fs)", duration))
                .font(.caption)
                .foregroundColor(durationColor)
                .fontWeight(duration < 1.0 || duration > 10.0 ? .bold : .regular)

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

    // Bouton d'export vidéo
    private var exportVideoButton: some View {
        VStack {
            Button(action: {
                exportSelectedSegments()
            }) {
                Image(systemName: "square.and.arrow.up.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.purple)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isExportingVideo || transcriptionSegments.filter { $0.isActive }.isEmpty)

            Text("Exporter")
                .font(.caption)
                .foregroundColor(isExportingVideo || transcriptionSegments.filter { $0.isActive }.isEmpty ? .gray : .purple)
        }
        .padding(.horizontal, 10)
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

                Génère un titre putaclic très court, une description engageante et des hashtags pertinents pour cette vidéo.
                Format:
                TITRE: [titre putaclic]
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

    // Fonction pour exporter les segments sélectionnés avec le titre et le son
    private func exportSelectedSegments() {
        guard let videoURL = videoURL, let asset = asset else {
            // Afficher une alerte si aucune vidéo n'est chargée
            alertType = .noVideo
            return
        }
        
        // Filtrer les segments actifs
        let activeSegments = transcriptionSegments.filter { $0.isActive }
        
        // Vérifier qu'il y a des segments actifs à exporter
        if activeSegments.isEmpty {
            return
        }
        
        // Ouvrir un dialogue pour choisir où enregistrer la vidéo exportée
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.mpeg4Movie]
        savePanel.nameFieldStringValue = "video_montage.mp4"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            // Commencer l'export
            isExportingVideo = true
            exportProgress = 0.0
            
            // Créer une composition pour l'export
            let composition = AVMutableComposition()
            
            // Créer une piste vidéo dans la composition
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                isExportingVideo = false
                return
            }
            
            // Créer une piste audio dans la composition si nécessaire
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid)
            
            // Récupérer les pistes vidéo et audio de l'asset original
            let videoTracks = asset.tracks(withMediaType: .video)
            let audioTracks = asset.tracks(withMediaType: .audio)
            
            guard let sourceVideoTrack = videoTracks.first else {
                isExportingVideo = false
                return
            }
            
            // Récupérer la piste audio source si elle existe
            let sourceAudioTrack = audioTracks.first
            
            // Créer un objet pour les instructions de composition vidéo
            let videoCompositionInstructions = AVMutableVideoCompositionInstruction()
            
            // Durée totale de la vidéo exportée
            var totalDuration: CMTime = .zero
            
            // Traiter chaque segment actif
            for (index, segment) in activeSegments.enumerated() {
                // Calculer les temps de début et de fin du segment
                let startTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
                let endTime = CMTime(seconds: segment.endTime + segment.durationAdjustment, preferredTimescale: 600)
                let segmentTimeRange = CMTimeRange(start: startTime, end: endTime)
                let segmentDuration = CMTimeSubtract(endTime, startTime)
                
                do {
                    // Ajouter le segment vidéo à la composition
                    try compositionVideoTrack.insertTimeRange(
                        segmentTimeRange,
                        of: sourceVideoTrack,
                        at: totalDuration
                    )
                    
                    // Ajouter le segment audio à la composition si disponible
                    if let sourceAudioTrack = sourceAudioTrack, let compositionAudioTrack = compositionAudioTrack {
                        try compositionAudioTrack.insertTimeRange(
                            segmentTimeRange,
                            of: sourceAudioTrack,
                            at: totalDuration
                        )
                    }
                    
                    // Ajouter l'audio externe si disponible
                    if let audioURL = audioURL, let audioAsset = AVAsset(url: audioURL) as? AVURLAsset, let compositionAudioTrack = compositionAudioTrack {
                        let audioTracks = audioAsset.tracks(withMediaType: .audio)
                        if let audioTrack = audioTracks.first {
                            // Calculer la durée de l'audio à insérer
                            let segmentDurationSeconds = segmentDuration.seconds
                            
                            // Si c'est le premier segment, on commence au début de l'audio
                            // Sinon, on utilise une position proportionnelle dans l'audio
                            let audioStartTime: CMTime
                            let audioDuration: Double
                            
                            if index == 0 {
                                // Premier segment: commencer au début de l'audio
                                audioStartTime = .zero
                                audioDuration = min(segmentDurationSeconds, audioAsset.duration.seconds)
                            } else {
                                // Segments suivants: calculer une position proportionnelle
                                // Ou boucler l'audio si nécessaire
                                let totalSegmentsDuration = activeSegments[0..<index]
                                    .reduce(0.0) { $0 + ($1.endTime - $1.startTime + $1.durationAdjustment) }
                                
                                // Si l'audio est plus court que la vidéo, on le boucle
                                let audioPosition = totalSegmentsDuration.truncatingRemainder(dividingBy: audioAsset.duration.seconds)
                                audioStartTime = CMTime(seconds: audioPosition, preferredTimescale: 600)
                                
                                // Calculer la durée disponible jusqu'à la fin de l'audio
                                let remainingAudioDuration = audioAsset.duration.seconds - audioPosition
                                
                                if remainingAudioDuration >= segmentDurationSeconds {
                                    // Si l'audio restant est suffisant pour ce segment
                                    audioDuration = segmentDurationSeconds
                                } else {
                                    // Si l'audio restant ne couvre pas tout le segment,
                                    // on utilise ce qui reste puis on boucle depuis le début
                                    
                                    // D'abord, insérer la partie restante de l'audio
                                    let remainingAudioTimeRange = CMTimeRange(
                                        start: audioStartTime,
                                        duration: CMTime(seconds: remainingAudioDuration, preferredTimescale: 600)
                                    )
                                    
                                    try compositionAudioTrack.insertTimeRange(
                                        remainingAudioTimeRange,
                                        of: audioTrack,
                                        at: totalDuration
                                    )
                                    
                                    // Ensuite, insérer le début de l'audio pour compléter le segment
                                    let additionalDuration = segmentDurationSeconds - remainingAudioDuration
                                    let additionalTimeRange = CMTimeRange(
                                        start: .zero,
                                        duration: CMTime(seconds: additionalDuration, preferredTimescale: 600)
                                    )
                                    
                                    try compositionAudioTrack.insertTimeRange(
                                        additionalTimeRange,
                                        of: audioTrack,
                                        at: CMTimeAdd(totalDuration, CMTime(seconds: remainingAudioDuration, preferredTimescale: 600))
                                    )
                                    
                                    // Comme on a déjà inséré l'audio, on définit audioDuration à 0
                                    // pour éviter une insertion supplémentaire
                                    audioDuration = 0
                                }
                            }
                            
                            // Insérer l'audio si nécessaire (si on n'a pas déjà tout inséré)
                            if audioDuration > 0 {
                                let audioTimeRange = CMTimeRange(
                                    start: audioStartTime,
                                    duration: CMTime(seconds: audioDuration, preferredTimescale: 600)
                                )
                                
                                try compositionAudioTrack.insertTimeRange(
                                    audioTimeRange,
                                    of: audioTrack,
                                    at: totalDuration
                                )
                            }
                        }
                    }
                    
                    // Mettre à jour la durée totale
                    totalDuration = CMTimeAdd(totalDuration, segmentDuration)
                    
                    // Mettre à jour la progression
                    exportProgress = Float(index + 1) / Float(activeSegments.count) * 0.5
                    
                } catch {
                    print("Erreur lors de l'insertion du segment: \(error.localizedDescription)")
                    isExportingVideo = false
                    return
                }
            }
            
            // Créer une composition vidéo pour appliquer les effets
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(
                width: sourceVideoTrack.naturalSize.width,
                height: sourceVideoTrack.naturalSize.height
            )
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
            
            // Créer les instructions de composition vidéo
            let instructions = AVMutableVideoCompositionInstruction()
            instructions.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
            
            // Créer un layer instruction pour la piste vidéo
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            
            // Appliquer les transformations en fonction de l'effet sélectionné
            if selectedEffect == "ZOOM" {
                applyZoomEffectForExport(sourceVideoTrack: sourceVideoTrack, activeSegments: activeSegments, layerInstruction: layerInstruction)
            } else if selectedEffect == "JUMP CUT" {
                applyJumpCutEffectForExport(sourceVideoTrack: sourceVideoTrack, activeSegments: activeSegments, layerInstruction: layerInstruction)
            } else if selectedEffect == "MIX" {
                applyMixEffectForExport(sourceVideoTrack: sourceVideoTrack, activeSegments: activeSegments, layerInstruction: layerInstruction)
            }
            
            // Ajouter l'instruction de layer à l'instruction de composition
            instructions.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instructions]
            
            // Ajouter le titre si activé
            if showTitleOverlay && !videoTitle.isEmpty {
                // Créer un calque pour le titre
                let titleLayer = CATextLayer()
                titleLayer.string = videoTitle
                titleLayer.font = CTFontCreateWithName(titleFontName == "System" ? "Helvetica" as CFString : titleFontName as CFString, titleFontSize, nil)
                titleLayer.fontSize = titleFontSize
                titleLayer.alignmentMode = .center
                titleLayer.foregroundColor = CGColor.white
                titleLayer.isWrapped = true
                
                // Calculer la taille du texte
                let textSize = (videoTitle as NSString).size(withAttributes: [
                    NSAttributedString.Key.font: NSFont(name: titleFontName == "System" ? "Helvetica" : titleFontName, size: CGFloat(titleFontSize)) ?? NSFont.systemFont(ofSize: CGFloat(titleFontSize))
                ])
                
                // Créer un fond pour le titre
                let backgroundLayer = CALayer()
                backgroundLayer.backgroundColor = titleBackgroundColor.cgColor?.copy(alpha: 0.8)
                
                // Définir les dimensions du fond (un peu plus grand que le texte)
                let padding: CGFloat = 20
                backgroundLayer.frame = CGRect(
                    x: (sourceVideoTrack.naturalSize.width - textSize.width - padding * 2) / 2,
                    y: sourceVideoTrack.naturalSize.height * 0.85, // Positionner en haut
                    width: textSize.width + padding * 2,
                    height: textSize.height + padding * 2
                )
                backgroundLayer.cornerRadius = 10
                backgroundLayer.borderWidth = titleBorderWidth
                backgroundLayer.borderColor = CGColor.white
                
                // Positionner le texte sur le fond
                titleLayer.frame = CGRect(
                    x: backgroundLayer.frame.origin.x + padding,
                    y: backgroundLayer.frame.origin.y + padding / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                
                // Déterminer la durée d'affichage du titre
                var titleDisplayDuration: CMTime
                switch titleDuration {
                case "5s":
                    titleDisplayDuration = CMTime(seconds: 5, preferredTimescale: 600)
                case "10s":
                    titleDisplayDuration = CMTime(seconds: 10, preferredTimescale: 600)
                case "Tout":
                    titleDisplayDuration = totalDuration
                default:
                    titleDisplayDuration = CMTime(seconds: 5, preferredTimescale: 600)
                }
                titleDisplayDuration = CMTimeMinimum(titleDisplayDuration, totalDuration)
                
                // Créer un calque parent pour contenir le fond et le texte
                let parentLayer = CALayer()
                parentLayer.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: sourceVideoTrack.naturalSize.width,
                    height: sourceVideoTrack.naturalSize.height
                )
                
                // Ajouter les calques dans l'ordre (fond puis texte)
                parentLayer.addSublayer(backgroundLayer)
                parentLayer.addSublayer(titleLayer)
                
                // Créer une animation pour l'opacité (fondu)
                let fadeInAnimation = CABasicAnimation(keyPath: "opacity")
                fadeInAnimation.fromValue = 0.0
                fadeInAnimation.toValue = 1.0
                fadeInAnimation.duration = 0.5
                fadeInAnimation.beginTime = 0
                fadeInAnimation.fillMode = .forwards
                fadeInAnimation.isRemovedOnCompletion = false
                
                let fadeOutAnimation = CABasicAnimation(keyPath: "opacity")
                fadeOutAnimation.fromValue = 1.0
                fadeOutAnimation.toValue = 0.0
                fadeOutAnimation.duration = 0.5
                fadeOutAnimation.beginTime = titleDisplayDuration.seconds - 0.5
                fadeOutAnimation.fillMode = .forwards
                fadeOutAnimation.isRemovedOnCompletion = false
                
                // Appliquer les animations
                backgroundLayer.add(fadeInAnimation, forKey: "fadeIn")
                backgroundLayer.add(fadeOutAnimation, forKey: "fadeOut")
                titleLayer.add(fadeInAnimation, forKey: "fadeIn")
                titleLayer.add(fadeOutAnimation, forKey: "fadeOut")
                
                // Créer un calque vidéo pour la composition
                let videoLayer = CALayer()
                videoLayer.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: sourceVideoTrack.naturalSize.width,
                    height: sourceVideoTrack.naturalSize.height
                )
                
                // Créer un calque racine pour contenir tous les autres calques
                let outputLayer = CALayer()
                outputLayer.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: sourceVideoTrack.naturalSize.width,
                    height: sourceVideoTrack.naturalSize.height
                )
                
                // Ajouter les calques dans l'ordre (vidéo puis titre)
                outputLayer.addSublayer(videoLayer)
                outputLayer.addSublayer(parentLayer)
                
                // Configurer l'animation du calque
                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                    postProcessingAsVideoLayer: videoLayer,
                    in: outputLayer
                )
            }
            
            // Créer une session d'export
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                isExportingVideo = false
                return
            }
            
            // Configurer la session d'export
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.videoComposition = videoComposition
            
            // Configurer l'audio mix si nécessaire
            if let compositionAudioTrack = compositionAudioTrack {
                let audioMix = AVMutableAudioMix()
                let audioMixInputParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                
                // Appliquer le volume audio
                if let audioURL = audioURL {
                    // Si un audio externe est utilisé, appliquer le volume défini par l'utilisateur
                    audioMixInputParameters.setVolume(audioVolume, at: .zero)
                } else {
                    // Sinon, utiliser le volume normal pour l'audio de la vidéo
                    audioMixInputParameters.setVolume(1.0, at: .zero)
                }
                
                audioMix.inputParameters = [audioMixInputParameters]
                exportSession.audioMix = audioMix
            }
            
            // Ajouter un observateur de progression
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    // La progression de l'export commence à 50% (après la préparation)
                    self.exportProgress = 0.5 + Float(exportSession.progress) * 0.5
                }
            }
            
            // Démarrer l'export
            exportSession.exportAsynchronously {
                // Arrêter le timer de progression
                progressTimer.invalidate()
                
                DispatchQueue.main.async {
                    self.isExportingVideo = false
                    self.exportProgress = 1.0
                    
                    switch exportSession.status {
                    case .completed:
                        self.alertType = .exportCompleted(message: "Export vidéo terminé avec succès")
                        withAnimation {
                            self.showExportSuccessNotification = true
                        }
                    case .failed:
                        self.alertType = .exportCompleted(message: "Échec de l'export vidéo: \(exportSession.error?.localizedDescription ?? "Erreur inconnue")")
                    case .cancelled:
                        self.alertType = .exportCompleted(message: "Export vidéo annulé")
                    default:
                        self.alertType = .exportCompleted(message: "Export vidéo terminé avec le statut: \(exportSession.status.rawValue)")
                    }
                }
            }
        }
    }

    // Nouvelles fonctions pour appliquer les effets lors de l'export
    private func applyZoomEffectForExport(sourceVideoTrack: AVAssetTrack, activeSegments: [TranscriptionSegment], layerInstruction: AVMutableVideoCompositionLayerInstruction) {
        // Appliquer un effet de zoom progressif suivi d'un dézoom progressif
        var currentTime: CMTime = .zero
        
        for (index, segment) in activeSegments.enumerated() {
            let segmentDuration = CMTime(
                seconds: segment.endTime - segment.startTime + segment.durationAdjustment,
                preferredTimescale: 600
            )
            
            // Définir la durée de l'animation de zoom (0,5 secondes)
            let animationDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            // S'assurer que l'animation ne dépasse pas la durée du segment
            let actualAnimationDuration = CMTimeCompare(animationDuration, segmentDuration) > 0 
                ? segmentDuration 
                : animationDuration
            
            // Calculer le temps de début du dézoom (à la fin du segment moins la durée de l'animation)
            let dezoomStartTime = CMTimeSubtract(CMTimeAdd(currentTime, segmentDuration), actualAnimationDuration)
            
            // Nombre d'étapes pour chaque phase
            let numberOfSteps = 15
            
            // Phase de zoom (au début du segment)
            let zoomStepDuration = CMTimeMultiplyByFloat64(actualAnimationDuration, multiplier: 1.0 / Double(numberOfSteps))
            for step in 0..<numberOfSteps {
                // Calculer le facteur de zoom pour cette étape (de 1.0 à 1.5)
                let zoomFactor = 1.0 + (0.5 * Double(step) / Double(numberOfSteps - 1))
                
                // Créer la transformation avec le zoom
                let transform = CGAffineTransform(scaleX: CGFloat(zoomFactor), y: CGFloat(zoomFactor))
                
                // Calculer la translation pour centrer l'image
                let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - zoomFactor)) / 2.0
                let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - zoomFactor)) / 2.0
                
                // Combiner zoom et translation pour centrer
                let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                
                // Appliquer la transformation à ce moment précis
                let stepTime = CMTimeAdd(currentTime, CMTimeMultiplyByFloat64(zoomStepDuration, multiplier: Double(step)))
                layerInstruction.setTransform(combinedTransform, at: stepTime)
            }
            
            // Maintenir le zoom maximum pendant la partie centrale du segment
            let maxZoomTransform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - 1.5)) / 2.0
            let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - 1.5)) / 2.0
            let maxZoomCombinedTransform = maxZoomTransform.translatedBy(x: translateX, y: translateY)
            
            // Appliquer la transformation maximale à la fin de la phase de zoom
            layerInstruction.setTransform(maxZoomCombinedTransform, at: CMTimeAdd(currentTime, actualAnimationDuration))
            
            // Phase de dézoom (à la fin du segment)
            let dezoomStepDuration = CMTimeMultiplyByFloat64(actualAnimationDuration, multiplier: 1.0 / Double(numberOfSteps))
            for step in 0..<numberOfSteps {
                // Calculer le facteur de dézoom pour cette étape (de 1.5 à 1.0)
                let zoomFactor = 1.5 - (0.5 * Double(step) / Double(numberOfSteps - 1))
                
                // Créer la transformation avec le zoom
                let transform = CGAffineTransform(scaleX: CGFloat(zoomFactor), y: CGFloat(zoomFactor))
                
                // Calculer la translation pour centrer l'image
                let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - zoomFactor)) / 2.0
                let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - zoomFactor)) / 2.0
                
                // Combiner zoom et translation pour centrer
                let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                
                // Appliquer la transformation à ce moment précis
                let stepTime = CMTimeAdd(dezoomStartTime, CMTimeMultiplyByFloat64(dezoomStepDuration, multiplier: Double(step)))
                layerInstruction.setTransform(combinedTransform, at: stepTime)
            }
            
            // Ajouter la durée du segment au temps courant
            currentTime = CMTimeAdd(currentTime, segmentDuration)
        }
    }
    
    private func applyJumpCutEffectForExport(sourceVideoTrack: AVAssetTrack, activeSegments: [TranscriptionSegment], layerInstruction: AVMutableVideoCompositionLayerInstruction) {
        // Pour Jump Cut, on alterne entre zoom et normal avec des transitions plus nettes
        var currentTime: CMTime = .zero
        
        for (index, segment) in activeSegments.enumerated() {
            let segmentDuration = CMTime(
                seconds: segment.endTime - segment.startTime + segment.durationAdjustment,
                preferredTimescale: 600
            )
            
            // Définir la durée de la transition (0,2 secondes)
            let transitionDuration = CMTime(seconds: 0.2, preferredTimescale: 600)
            
            // S'assurer que la transition ne dépasse pas la durée du segment
            let actualTransitionDuration = CMTimeCompare(transitionDuration, CMTimeMultiplyByFloat64(segmentDuration, multiplier: 0.5)) > 0 
                ? CMTimeMultiplyByFloat64(segmentDuration, multiplier: 0.5) 
                : transitionDuration
            
            // Calculer le temps de fin de la transition d'entrée et le début de la transition de sortie
            let transitionInEndTime = CMTimeAdd(currentTime, actualTransitionDuration)
            let transitionOutStartTime = CMTimeSubtract(CMTimeAdd(currentTime, segmentDuration), actualTransitionDuration)
            
            // Nombre d'étapes pour chaque transition
            let numberOfSteps = 10
            
            if index % 2 == 0 {
                // Segments pairs: zoom centré avec transition progressive
                let maxZoomFactor: CGFloat = 1.5
                
                // Transition d'entrée (de normal à zoom)
                let transitionInStepDuration = CMTimeMultiplyByFloat64(actualTransitionDuration, multiplier: 1.0 / Double(numberOfSteps))
                for step in 0..<numberOfSteps {
                    // Calculer le facteur de zoom pour cette étape (de 1.0 à maxZoomFactor)
                    let zoomFactor = 1.0 + (Double(maxZoomFactor - 1.0) * Double(step) / Double(numberOfSteps - 1))
                    
                    // Créer la transformation avec le zoom
                    let transform = CGAffineTransform(scaleX: CGFloat(zoomFactor), y: CGFloat(zoomFactor))
                    
                    // Calculer la translation pour centrer l'image
                    let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - zoomFactor)) / 2.0
                    let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - zoomFactor)) / 2.0
                    
                    // Combiner zoom et translation pour centrer
                    let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                    
                    // Appliquer la transformation à ce moment précis
                    let stepTime = CMTimeAdd(currentTime, CMTimeMultiplyByFloat64(transitionInStepDuration, multiplier: Double(step)))
                    layerInstruction.setTransform(combinedTransform, at: stepTime)
                }
                
                // Maintenir le zoom maximum pendant la partie centrale du segment
                let maxZoomTransform = CGAffineTransform(scaleX: maxZoomFactor, y: maxZoomFactor)
                let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - Double(maxZoomFactor))) / 2.0
                let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - Double(maxZoomFactor))) / 2.0
                let maxZoomCombinedTransform = maxZoomTransform.translatedBy(x: translateX, y: translateY)
                
                // Appliquer la transformation maximale à la fin de la transition d'entrée
                layerInstruction.setTransform(maxZoomCombinedTransform, at: transitionInEndTime)
                
                // Transition de sortie (de zoom à normal)
                let transitionOutStepDuration = CMTimeMultiplyByFloat64(actualTransitionDuration, multiplier: 1.0 / Double(numberOfSteps))
                for step in 0..<numberOfSteps {
                    // Calculer le facteur de zoom pour cette étape (de maxZoomFactor à 1.0)
                    let zoomFactor = Double(maxZoomFactor) - (Double(maxZoomFactor - 1.0) * Double(step) / Double(numberOfSteps - 1))
                    
                    // Créer la transformation avec le zoom
                    let transform = CGAffineTransform(scaleX: CGFloat(zoomFactor), y: CGFloat(zoomFactor))
                    
                    // Calculer la translation pour centrer l'image
                    let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - zoomFactor)) / 2.0
                    let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - zoomFactor)) / 2.0
                    
                    // Combiner zoom et translation pour centrer
                    let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                    
                    // Appliquer la transformation à ce moment précis
                    let stepTime = CMTimeAdd(transitionOutStartTime, CMTimeMultiplyByFloat64(transitionOutStepDuration, multiplier: Double(step)))
                    layerInstruction.setTransform(combinedTransform, at: stepTime)
                }
            } else {
                // Segments impairs: normal
                let normalTransform = CGAffineTransform.identity
                layerInstruction.setTransform(normalTransform, at: currentTime)
            }
            
            // Ajouter la durée du segment au temps courant
            currentTime = CMTimeAdd(currentTime, segmentDuration)
        }
    }
    
    private func applyMixEffectForExport(sourceVideoTrack: AVAssetTrack, activeSegments: [TranscriptionSegment], layerInstruction: AVMutableVideoCompositionLayerInstruction) {
        // Pour l'effet MIX, on alterne entre différents effets
        var currentTime: CMTime = .zero
        
        for (index, segment) in activeSegments.enumerated() {
            let segmentDuration = CMTime(
                seconds: segment.endTime - segment.startTime + segment.durationAdjustment,
                preferredTimescale: 600
            )
            
            // Définir la durée de la transition (0,3 secondes)
            let transitionDuration = CMTime(seconds: 0.3, preferredTimescale: 600)
            
            // S'assurer que la transition ne dépasse pas la durée du segment
            let actualTransitionDuration = CMTimeCompare(transitionDuration, CMTimeMultiplyByFloat64(segmentDuration, multiplier: 0.25)) > 0 
                ? CMTimeMultiplyByFloat64(segmentDuration, multiplier: 0.25) 
                : transitionDuration
            
            // Nombre d'étapes pour chaque transition
            let numberOfSteps = 10
            
            // Choisir aléatoirement un effet parmi trois possibilités
            let effectType = Int.random(in: 0...2)
            
            switch effectType {
            case 0:
                // Effet 1: Zoom progressif
                
                // Transition d'entrée (de normal à zoom)
                let transitionInStepDuration = CMTimeMultiplyByFloat64(actualTransitionDuration, multiplier: 1.0 / Double(numberOfSteps))
                for step in 0..<numberOfSteps {
                    // Calculer le facteur de zoom pour cette étape (de 1.0 à 1.4)
                    let zoomFactor = 1.0 + (0.4 * Double(step) / Double(numberOfSteps - 1))
                    let transform = CGAffineTransform(scaleX: CGFloat(zoomFactor), y: CGFloat(zoomFactor))
                    
                    // Centrer l'image
                    let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - zoomFactor)) / 2.0
                    let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - zoomFactor)) / 2.0
                    let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                    
                    let stepTime = CMTimeAdd(currentTime, CMTimeMultiplyByFloat64(transitionInStepDuration, multiplier: Double(step)))
                    layerInstruction.setTransform(combinedTransform, at: stepTime)
                }
                
                // Maintenir le zoom maximum pendant le reste du segment
                let maxZoomTransform = CGAffineTransform(scaleX: 1.4, y: 1.4)
                let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - 1.4)) / 2.0
                let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - 1.4)) / 2.0
                let maxZoomCombinedTransform = maxZoomTransform.translatedBy(x: translateX, y: translateY)
                
                // Appliquer la transformation maximale pour le reste du segment
                layerInstruction.setTransform(maxZoomCombinedTransform, at: CMTimeAdd(currentTime, actualTransitionDuration))
                
            case 1:
                // Effet 2: Jump Cut (seulement pour les segments assez longs)
                if segmentDuration.seconds >= 2.0 {
                    // Diviser le segment en deux parties
                    let midPoint = CMTimeAdd(currentTime, CMTimeMultiplyByFloat64(segmentDuration, multiplier: 0.5))
                    
                    // Première partie: normal
                    let normalTransform = CGAffineTransform.identity
                    layerInstruction.setTransform(normalTransform, at: currentTime)
                    
                    // Deuxième partie: zoom léger
                    let zoomFactor: CGFloat = 1.2
                    let transform = CGAffineTransform(scaleX: zoomFactor, y: zoomFactor)
                    
                    // Centrer l'image
                    let translateX = (sourceVideoTrack.naturalSize.width * (1.0 - Double(zoomFactor))) / 2.0
                    let translateY = (sourceVideoTrack.naturalSize.height * (1.0 - Double(zoomFactor))) / 2.0
                    let combinedTransform = transform.translatedBy(x: translateX, y: translateY)
                    
                    layerInstruction.setTransform(combinedTransform, at: midPoint)
                } else {
                    // Si le segment est trop court, appliquer une transformation normale
                    let normalTransform = CGAffineTransform.identity
                    layerInstruction.setTransform(normalTransform, at: currentTime)
                }
                
            case 2:
                // Effet 3: Normal (pas de transformation)
                let normalTransform = CGAffineTransform.identity
                layerInstruction.setTransform(normalTransform, at: currentTime)
                
            default:
                break
            }
            
            // Ajouter la durée du segment au temps courant
            currentTime = CMTimeAdd(currentTime, segmentDuration)
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
