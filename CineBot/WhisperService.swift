import Foundation
import AVFoundation

/// Service pour la transcription audio via l'API Whisper d'OpenAI
class WhisperService {
    // MARK: - Types
    
    /// Erreurs possibles du service Whisper
    enum WhisperError: Error {
        case invalidAPIKey
        case fileTooLarge(size: Int, maxSize: Int)
        case audioExtractionFailed
        case invalidResponse
        case networkError(Error)
        case serverError(statusCode: Int, message: String?)
        case decodingError(Error)
        
        var localizedDescription: String {
            switch self {
            case .invalidAPIKey:
                return "Clé API OpenAI invalide ou manquante"
            case .fileTooLarge(let size, let maxSize):
                return "Fichier audio trop volumineux: \(size/1_000_000) MB (maximum: \(maxSize/1_000_000) MB)"
            case .audioExtractionFailed:
                return "Échec de l'extraction audio depuis la vidéo"
            case .invalidResponse:
                return "Réponse invalide du serveur OpenAI"
            case .networkError(let error):
                return "Erreur réseau: \(error.localizedDescription)"
            case .serverError(let statusCode, let message):
                return "Erreur serveur (\(statusCode)): \(message ?? "Aucun détail")"
            case .decodingError(let error):
                return "Erreur de décodage: \(error.localizedDescription)"
            }
        }
    }
    
    /// Options de transcription
    struct TranscriptionOptions {
        /// Langue de l'audio (laissez nil pour auto-détection)
        var language: String?
        
        /// Température de l'échantillonnage (0-1)
        var temperature: Float = 0
        
        /// Format de réponse (json, text, srt, verbose_json, vtt)
        var responseFormat: String = "json"
        
        /// Génération d'horodatages
        var timestamp: Bool = false
        
        static var `default`: TranscriptionOptions {
            return TranscriptionOptions()
        }
    }
    
    /// Réponse de l'API Whisper
    struct WhisperResponse: Decodable {
        let text: String
        // Vous pouvez ajouter d'autres champs selon vos besoins et le format de réponse choisi
    }
    
    // MARK: - Propriétés
    
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let maxFileSize = 25 * 1_000_000 // 25 MB, limite d'OpenAI
    
    // MARK: - Initialisation
    
    /// Initialise le service Whisper avec une clé API OpenAI
    /// - Parameter apiKey: Clé API OpenAI
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Méthodes publiques
    
    /// Transcrit un fichier audio avec l'API Whisper
    /// - Parameters:
    ///   - audioURL: URL du fichier audio à transcrire
    ///   - options: Options de transcription
    ///   - completion: Closure appelée avec le résultat de la transcription
    func transcribeAudio(
        from audioURL: URL,
        options: TranscriptionOptions = .default,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Vérifier la taille du fichier
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            if let size = attributes[.size] as? Int, size > maxFileSize {
                completion(.failure(WhisperError.fileTooLarge(size: size, maxSize: maxFileSize)))
                return
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        // Créer la requête
        var request = createTranscriptionRequest(options: options)
        
        // Préparer les données multipart
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try createRequestBody(audioURL: audioURL, options: options, boundary: boundary)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Effectuer la requête
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(WhisperError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(WhisperError.invalidResponse))
                return
            }
            
            if httpResponse.statusCode != 200 {
                // Traiter l'erreur du serveur
                if let data = data, let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorJSON["error"] as? [String: Any],
                   let message = errorMessage["message"] as? String {
                    completion(.failure(WhisperError.serverError(statusCode: httpResponse.statusCode, message: message)))
                } else {
                    completion(.failure(WhisperError.serverError(statusCode: httpResponse.statusCode, message: nil)))
                }
                return
            }
            
            guard let data = data else {
                completion(.failure(WhisperError.invalidResponse))
                return
            }
            
            do {
                if options.responseFormat == "text" {
                    // Si le format est text, on retourne directement le texte
                    if let result = String(data: data, encoding: .utf8) {
                        completion(.success(result))
                    } else {
                        completion(.failure(WhisperError.invalidResponse))
                    }
                } else {
                    // Sinon on décode le JSON
                    let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
                    completion(.success(response.text))
                }
            } catch {
                completion(.failure(WhisperError.decodingError(error)))
            }
        }
        
        task.resume()
    }
    
    /// Transcrit une vidéo en extrayant d'abord l'audio
    /// - Parameters:
    ///   - videoURL: URL du fichier vidéo
    ///   - options: Options de transcription
    ///   - completion: Closure appelée avec le résultat de la transcription
    func transcribeVideo(
        from videoURL: URL,
        options: TranscriptionOptions = .default,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        extractAudioFromVideo(videoURL: videoURL) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let audioURL):
                self.transcribeAudio(from: audioURL, options: options) { transcriptionResult in
                    // Nettoyer le fichier audio temporaire
                    try? FileManager.default.removeItem(at: audioURL)
                    
                    completion(transcriptionResult)
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Méthodes async/await (iOS 15+, macOS 12+)
    
    /// Version async/await de la transcription audio
    @available(iOS 15.0, macOS 12.0, *)
    func transcribeAudio(from audioURL: URL, options: TranscriptionOptions = .default) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            transcribeAudio(from: audioURL, options: options) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Version async/await de la transcription vidéo
    @available(iOS 15.0, macOS 12.0, *)
    func transcribeVideo(from videoURL: URL, options: TranscriptionOptions = .default) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            transcribeVideo(from: videoURL, options: options) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Méthodes privées
    
    private func createTranscriptionRequest(options: TranscriptionOptions) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func createRequestBody(audioURL: URL, options: TranscriptionOptions, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: audioURL)
        
        var data = Data()
        
        // Ajouter le paramètre model
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Ajouter les options
        if let language = options.language {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        if options.temperature != 0 {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(options.temperature)\r\n".data(using: .utf8)!)
        }
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(options.responseFormat)\r\n".data(using: .utf8)!)
        
        if options.timestamp {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"timestamp\"\r\n\r\n".data(using: .utf8)!)
            data.append("true\r\n".data(using: .utf8)!)
        }
        
        // Ajouter le fichier audio
        let filename = audioURL.lastPathComponent
        let mimeType = getMimeType(for: audioURL)
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(audioData)
        data.append("\r\n".data(using: .utf8)!)
        
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return data
    }
    
    private func extractAudioFromVideo(videoURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        
        let asset = AVAsset(url: videoURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(WhisperError.audioExtractionFailed))
            return
        }
        
        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                completion(.success(audioURL))
            case .failed, .cancelled:
                completion(.failure(exportSession.error ?? WhisperError.audioExtractionFailed))
            default:
                completion(.failure(WhisperError.audioExtractionFailed))
            }
        }
    }
    
    private func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "m4a":
            return "audio/m4a"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "mp4":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }
} 