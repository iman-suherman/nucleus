import Foundation
import SyncKit

enum NucleusAIServiceError: LocalizedError {
    case notConnected
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect Nucleus Cloud to use Nucleus AI."
        case .invalidResponse:
            return "Nucleus AI returned an unexpected response."
        case .serverError(let message):
            return message
        }
    }
}

@MainActor
final class NucleusAIService: ObservableObject {
    static let shared = NucleusAIService()

    static let productionBaseURL = URL(string: "https://nucleus-ai.suherman.net")!

    @Published private(set) var isLoading = false
    @Published private(set) var lastAnswer: String?
    @Published private(set) var lastError: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = productionBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func ask(question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let credentials = try NucleusCloudTokenStore.shared.load()
            let answer = try await requestOverview(question: trimmed, apiToken: credentials.apiToken)
            lastAnswer = answer
        } catch {
            lastAnswer = nil
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearLastResult() {
        lastAnswer = nil
        lastError = nil
    }

    private func requestOverview(question: String, apiToken: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/overview/ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["question": question])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NucleusAIServiceError.invalidResponse
        }

        if http.statusCode == 401 {
            throw NucleusCloudAPIError.unauthorized
        }

        guard (200 ... 299).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(NucleusAIErrorResponse.self, from: data),
               let message = payload.error,
               !message.isEmpty {
                throw NucleusAIServiceError.serverError(message)
            }
            let fallback = String(data: data, encoding: .utf8) ?? "Request failed"
            throw NucleusAIServiceError.serverError(fallback)
        }

        let payload = try JSONDecoder().decode(NucleusAIOverviewResponse.self, from: data)
        let formatted = Self.formattedAnswer(from: payload)
        guard !formatted.isEmpty else {
            throw NucleusAIServiceError.invalidResponse
        }
        return formatted
    }

    private static func formattedAnswer(from payload: NucleusAIOverviewResponse) -> String {
        guard let answer = payload.answer else { return "" }
        var parts: [String] = []

        if let summary = answer.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append(summary)
        }

        for section in answer.sections ?? [] {
            let body = section.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !body.isEmpty else { continue }
            if let title = section.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                parts.append("\(title): \(body)")
            } else {
                parts.append(body)
            }
            if parts.count >= 3 { break }
        }

        return parts.joined(separator: "\n\n")
    }
}

private struct NucleusAIErrorResponse: Decodable {
    let error: String?
}

private struct NucleusAIOverviewResponse: Decodable {
    struct AnswerPayload: Decodable {
        struct SectionPayload: Decodable {
            let title: String?
            let body: String?
        }

        let summary: String?
        let sections: [SectionPayload]?
    }

    let answer: AnswerPayload?
}
