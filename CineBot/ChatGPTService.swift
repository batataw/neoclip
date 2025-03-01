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
    
    func correctText(_ text: String) async throws -> String {
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
        
        let prompt = """
        Corrige l'orthographe et la grammaire du texte suivant en français, \
        en conservant la ponctuation et les sauts de ligne. \
        Retourne uniquement le texte corrigé, sans explications :
        
        \(text)
        """
        
        let request = ChatGPTRequest(
            model: "gpt-4o",
            messages: [
                ChatGPTRequest.Message(
                    role: "system",
                    content: "Tu es un correcteur orthographique et grammatical expert en français."
                ),
                ChatGPTRequest.Message(
                    role: "user",
                    content: prompt
                )
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
                throw ChatGPTError.httpError(httpResponse.statusCode)
            }
            
            let decodedResponse = try JSONDecoder().decode(ChatGPTResponse.self, from: data)
            
            guard let correctedText = decodedResponse.choices.first?.message.content else {
                throw ChatGPTError.decodingError
            }
            
            return correctedText
        } catch {
            throw ChatGPTError.networkError(error)
        }
    }
} 