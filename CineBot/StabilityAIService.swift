import Foundation
import AppKit

class StabilityAIService: ObservableObject {
    @Published private(set) var isGeneratingImage = false
    
    private let apiKey: String
    private let baseURL = "https://api.stability.ai/v2beta/stable-image/generate/ultra"
    private let chatGPTService: ChatGPTService
    
    init(apiKey: String = APIKeys.stabilityAI, openAIKey: String = APIKeys.openAI) {
        self.apiKey = apiKey
        self.chatGPTService = ChatGPTService(apiKey: openAIKey)
    }
    
    enum StabilityAIError: Error {
        case invalidURL
        case invalidResponse
        case httpError(Int, String)
        case imageCreationError
        case networkError(Error)
        case translationError
    }
    
    // Méthode pour traduire le prompt en anglais
    private func translateToEnglishWithChatGPT(_ prompt: String) async throws -> String {
        do {
            let translationPrompt = """
            Create a comprehensive prompt for Stable Diffusion XL to generate an image. 
            The prompt should be in English. Provide ONLY the prompt without any additional text, explanation, or quotes:
            
            \(prompt)
            """
            
            let translation = try await chatGPTService.getResponse(for: translationPrompt)
            print("Prompt original: \(prompt)")
            print("Traduction: \(translation)")
            return translation
        } catch {
            print("Erreur de traduction: \(error)")
            throw StabilityAIError.translationError
        }
    }
    
    // Fonction pour générer une image avec Stability AI (v2beta)
    func generateImage(for prompt: String, format: String = "portrait", translateToEnglish: Bool = true) async throws -> NSImage? {
        DispatchQueue.main.async {
            self.isGeneratingImage = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isGeneratingImage = false
            }
        }
        
        // Traduire le prompt en anglais si nécessaire
        let englishPrompt: String
        if translateToEnglish {
            englishPrompt = try await translateToEnglishWithChatGPT(prompt)
        } else {
            englishPrompt = prompt
        }

        print("Prompt anglais: \(englishPrompt)")
        
        guard let url = URL(string: baseURL) else {
            throw StabilityAIError.invalidURL
        }
        
        // Créer une requête multipart/form-data
        let boundary = UUID().uuidString
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Paramètres pour l'aspect ratio
        var aspectRatio = "1:1"
        switch format {
        case "portrait", "9:16":
            aspectRatio = "9:16"
        case "landscape", "16:9":
            aspectRatio = "16:9"
        default:
            aspectRatio = "1:1"
        }
        
        // Construire le corps de la requête multipart
        var body = Data()
        
        // Ajouter un champ "none" vide (comme dans l'exemple Python)
        //addFormField(name: "none", value: "", boundary: boundary, to: &body)
        
        // Ajouter le prompt en anglais
        addFormField(name: "prompt", value: englishPrompt, boundary: boundary, to: &body)
        
        // Ajouter le format de sortie
        addFormField(name: "output_format", value: "png", boundary: boundary, to: &body)
        
        // Ajouter le ratio d'aspect
        addFormField(name: "aspect_ratio", value: aspectRatio, boundary: boundary, to: &body)
        
        // Finaliser le corps de la requête
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        urlRequest.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StabilityAIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("Erreur HTTP: \(httpResponse.statusCode)")
                var errorMessage = "Erreur inconnue"
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Détails de l'erreur: \(errorText)")
                    errorMessage = errorText
                }
                throw StabilityAIError.httpError(httpResponse.statusCode, errorMessage)
            }
            
            // L'API renvoie directement l'image
            if let image = NSImage(data: data) {
                return image
            } else {
                throw StabilityAIError.imageCreationError
            }
        } catch {
            print("Erreur dans generateImage: \(error.localizedDescription)")
            throw StabilityAIError.networkError(error)
        }
    }
    
    // Méthode pour ajouter un champ au formulaire multipart
    private func addFormField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}

// Extension pour faciliter l'ajout de données au corps multipart
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
