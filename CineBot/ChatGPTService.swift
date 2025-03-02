import Foundation

class ChatGPTService: ObservableObject {
    @Published private(set) var isProcessing = false

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

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
}
