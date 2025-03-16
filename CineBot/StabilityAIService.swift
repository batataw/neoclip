import Foundation
import AppKit

class StabilityAIService: ObservableObject {
    @Published private(set) var isGeneratingImage = false
    
    private let apiKey: String
    private let baseURL = "https://api.stability.ai/v1/generation/stable-diffusion-xl-1024-v1-0/text-to-image"
    
    init(apiKey: String = APIKeys.stabilityAI) {
        self.apiKey = apiKey
    }
    
    enum StabilityAIError: Error {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case decodingError
        case networkError(Error)
    }
    
    // Structure pour la requête Stability AI
    struct StabilityAIRequest: Codable {
        let text_prompts: [TextPrompt]
        let cfg_scale: Float
        let height: Int
        let width: Int
        let samples: Int
        let steps: Int
        
        struct TextPrompt: Codable {
            let text: String
            let weight: Float
        }
    }
    
    // Structure pour la réponse Stability AI
    struct StabilityAIResponse: Codable {
        struct Artifact: Codable {
            let base64: String
            let seed: Int
            let finishReason: String
        }
        
        let artifacts: [Artifact]
    }
    
    // Fonction pour générer une image avec Stability AI
    func generateImage(for prompt: String, format: String = "9:16") async throws -> NSImage? {
        DispatchQueue.main.async {
            self.isGeneratingImage = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isGeneratingImage = false
            }
        }
        
        guard let url = URL(string: baseURL) else {
            throw StabilityAIError.invalidURL
        }
        
        // Déterminer les dimensions selon le format demandé
        var width = 1024
        var height = 1024
        
        // Format 9:16 (portrait, comme pour les stories/reels)
        if format == "9:16" {
            width = 576  // ou 768
            height = 1024
        }
        // Format 16:9 (paysage, comme pour YouTube)
        else if format == "16:9" {
            width = 1024
            height = 576  // ou 768
        }
        
        // Créer la requête pour Stability AI
        let request = StabilityAIRequest(
            text_prompts: [
                StabilityAIRequest.TextPrompt(text: prompt, weight: 1.0)
            ],
            cfg_scale: 7.0,
            height: height,
            width: width,
            samples: 1,
            steps: 30
        )
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StabilityAIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("Erreur HTTP: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Détails de l'erreur: \(errorText)")
                }
                throw StabilityAIError.httpError(httpResponse.statusCode)
            }
            
            let decodedResponse = try JSONDecoder().decode(StabilityAIResponse.self, from: data)
            
            guard let base64String = decodedResponse.artifacts.first?.base64 else {
                throw StabilityAIError.decodingError
            }
            
            // Convertir le Base64 en données d'image
            guard let imageData = Data(base64Encoded: base64String) else {
                throw StabilityAIError.decodingError
            }
            
            // Convertir les données en NSImage
            if let image = NSImage(data: imageData) {
                return image
            } else {
                throw StabilityAIError.decodingError
            }
        } catch {
            print("Erreur dans generateImage: \(error.localizedDescription)")
            throw StabilityAIError.networkError(error)
        }
    }
}
