import Foundation
import AppKit

class ChatGPTService: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var isGeneratingImage = false

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let dalleURL = "https://api.openai.com/v1/images/generations"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    struct ChatGPTRequest: Codable {
        let model: String
        let messages: [Message]

        struct Message: Codable {
            let role: String
            let content: String
        }
    }

    struct ChatGPTResponse: Codable {
        struct Choice: Codable {
            let message: Message

            struct Message: Codable {
                let content: String
            }
        }

        let choices: [Choice]
    }

    enum ChatGPTError: Error {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case decodingError
        case networkError(Error)
    }

    func getResponse(for prompt: String) async throws -> String {
        DispatchQueue.main.async {
            self.isProcessing = true
        }

        defer {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }

        guard let url = URL(string: baseURL) else {
            throw ChatGPTError.invalidURL
        }

        let request = ChatGPTRequest(
            model: "gpt-4o",
            messages: [
                ChatGPTRequest.Message(
                    role: "system",
                    content:
                        "Tu es un assistant intelligent et créatif qui aide à créer du contenu de qualité. Tu réponds de manière concise et précise aux demandes de l'utilisateur."
                ),
                ChatGPTRequest.Message(role: "user", content: prompt),
            ]
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatGPTError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("Erreur HTTP: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Détails de l'erreur: \(errorText)")
                }
                throw ChatGPTError.httpError(httpResponse.statusCode)
            }

            let decodedResponse = try JSONDecoder().decode(ChatGPTResponse.self, from: data)

            guard let content = decodedResponse.choices.first?.message.content else {
                throw ChatGPTError.decodingError
            }

            return content
        } catch {
            print("Erreur dans getResponse: \(error.localizedDescription)")
            throw ChatGPTError.networkError(error)
        }
    }

    // Structure pour la requête DALL-E
    struct DALLERequest: Codable {
        let model: String
        let prompt: String
        let n: Int
        let size: String
    }

    // Structure pour la réponse DALL-E
    struct DALLEResponse: Codable {
        struct ImageData: Codable {
            let url: String
        }
        
        let created: Int
        let data: [ImageData]
    }

    // Fonction pour générer une image avec DALL-E
    func generateImage(for prompt: String) async throws -> NSImage? {
        DispatchQueue.main.async {
            self.isGeneratingImage = true
        }

        defer {
            DispatchQueue.main.async {
                self.isGeneratingImage = false
            }
        }

        guard let url = URL(string: dalleURL) else {
            throw ChatGPTError.invalidURL
        }

        // Créer la requête pour DALL-E
        let request = DALLERequest(
            model: "dall-e-3",
            prompt: prompt,
            n: 1,
            size: "1024x1792" // Format 9:16
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ChatGPTError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("Erreur HTTP: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Détails de l'erreur: \(errorText)")
                }
                throw ChatGPTError.httpError(httpResponse.statusCode)
            }

            let decodedResponse = try JSONDecoder().decode(DALLEResponse.self, from: data)

            guard let imageURL = URL(string: decodedResponse.data.first?.url ?? "") else {
                throw ChatGPTError.decodingError
            }

            // Télécharger l'image
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            
            // Convertir les données en NSImage
            if let image = NSImage(data: imageData) {
                return image
            } else {
                throw ChatGPTError.decodingError
            }
        } catch {
            print("Erreur dans generateImage: \(error.localizedDescription)")
            throw ChatGPTError.networkError(error)
        }
    }
}
