import Foundation
import XCTest
@testable import HearSub

final class OpenAICompatibleTranslationServiceTests: XCTestCase {
    override func tearDown() {
        TranslationURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testDeepSeekDisablesThinkingForShortSubtitles() async throws {
        let service = makeService(response: completedResponse) { request in
            let payload = try self.payload(of: request)
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual((payload["thinking"] as? [String: String])?["type"], "disabled")
            XCTAssertEqual(payload["max_tokens"] as? Int, 64)
            XCTAssertEqual(payload["stream"] as? Bool, false)
            XCTAssertEqual(request.timeoutInterval, 12)
        }

        let result = try await translate(using: service, model: "deepseek-flash", baseURL: "https://api.deepseek.com")
        XCTAssertEqual(result, "Bonjour")
    }

    func testDeepSeekThroughGatewayAlsoDisablesThinking() async throws {
        let service = makeService(response: completedResponse) { request in
            let payload = try self.payload(of: request)
            XCTAssertEqual((payload["thinking"] as? [String: String])?["type"], "disabled")
        }
        let result = try await translate(using: service, model: "deepseek/deepseek-v4-pro")
        XCTAssertEqual(result, "Bonjour")
    }

    func testGenericModelsDoNotReceiveDeepSeekParameter() async throws {
        let service = makeService(response: completedResponse) { request in
            let payload = try self.payload(of: request)
            XCTAssertNil(payload["thinking"])
            XCTAssertEqual(payload["max_tokens"] as? Int, 64)
            XCTAssertEqual(payload["temperature"] as? Double, 0.1)
        }
        let result = try await translate(using: service)
        XCTAssertEqual(result, "Bonjour")
    }

    func testLegacyReasonerHasBudgetForReasoningButReturnsOnlyTranslation() async throws {
        let response = #"{"choices":[{"message":{"content":"Bonjour","reasoning_content":"Private reasoning"},"finish_reason":"stop"}]}"#
        let service = makeService(response: response) { request in
            let payload = try self.payload(of: request)
            XCTAssertNil(payload["thinking"])
            XCTAssertEqual(payload["max_tokens"] as? Int, 8192)
            XCTAssertEqual(request.timeoutInterval, 60)
        }
        let result = try await translate(using: service, model: "deepseek-reasoner")
        XCTAssertEqual(result, "Bonjour")
    }

    func testReasoningExhaustingTokenBudgetIsReportedAsLimit() async throws {
        let response = #"{"choices":[{"message":{"content":"","reasoning_content":"Thinking"},"finish_reason":"length"}]}"#
        try await assertFailure(response: response) {
            if case .outputLimitReached = $0 { return true }
            return false
        }
    }

    func testTruncatedTranslationIsNotDisplayedAsComplete() async throws {
        let response = #"{"choices":[{"message":{"content":"Bon"},"finish_reason":"length"}]}"#
        try await assertFailure(response: response) {
            if case .outputLimitReached = $0 { return true }
            return false
        }
    }

    func testNullContentWithReasoningIsNotUsedAsSubtitle() async throws {
        let response = #"{"choices":[{"message":{"content":null,"reasoning_content":"Thinking"},"finish_reason":"stop"}]}"#
        try await assertFailure(response: response) {
            if case .reasoningOnlyResponse = $0 { return true }
            return false
        }
    }

    func testEmptyTranslationIncludesFinishReason() async throws {
        let response = #"{"choices":[{"message":{"content":"  "},"finish_reason":"content_filter"}]}"#
        try await assertFailure(response: response) {
            if case .emptyTranslation("content_filter") = $0 { return true }
            return false
        }
    }

    func testMissingContentAndEmptyChoicesAreHandled() async throws {
        for response in [#"{"choices":[{"message":{}}]}"#, #"{"choices":[]}"#] {
            try await assertFailure(response: response) {
                if case .emptyTranslation(nil) = $0 { return true }
                return false
            }
        }
    }

    func testMalformedResponseIsReportedAsInvalid() async throws {
        for response in ["not json", #"{"unexpected":true}"#] {
            try await assertFailure(response: response) {
                if case .invalidResponse = $0 { return true }
                return false
            }
        }
    }

    func testWrappingQuotesAreRemoved() async throws {
        let response = #"{"choices":[{"message":{"content":" \"Bonjour\" "}}]}"#
        let result = try await translate(using: makeService(response: response))
        XCTAssertEqual(result, "Bonjour")
    }

    func testQuoteOnlyResponseIsRejected() async throws {
        let response = #"{"choices":[{"message":{"content":"\"\""}}]}"#
        try await assertFailure(response: response) {
            if case .emptyTranslation(nil) = $0 { return true }
            return false
        }
    }

    func testHTTPFailureIsPreserved() async throws {
        let service = makeService(response: "service unavailable", statusCode: 503)
        do {
            _ = try await translate(using: service)
            XCTFail("Expected an HTTP failure")
        } catch OpenAICompatibleTranslationService.ServiceError.requestFailed(let status, let body) {
            XCTAssertEqual(status, 503)
            XCTAssertEqual(body, "service unavailable")
        }
    }

    private let completedResponse = #"{"choices":[{"message":{"content":"Bonjour"},"finish_reason":"stop"}]}"#

    private func payload(of request: URLRequest) throws -> [String: Any] {
        let body: Data
        if let data = request.httpBody {
            body = data
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func makeService(
        response: String,
        statusCode: Int = 200,
        validate: ((URLRequest) throws -> Void)? = nil
    ) -> OpenAICompatibleTranslationService {
        TranslationURLProtocol.setHandler { request in
            try validate?(request)
            return (statusCode, Data(response.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        return OpenAICompatibleTranslationService(session: URLSession(configuration: configuration))
    }

    private func translate(
        using service: OpenAICompatibleTranslationService,
        model: String = "generic-model",
        baseURL: String = "https://example.com/v1"
    ) async throws -> String {
        try await service.translate("Hello", from: "en", to: "fr", settings: .init(
            baseURL: baseURL, apiKey: "test-key", model: model
        ))
    }

    private func assertFailure(
        response: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        matches: (OpenAICompatibleTranslationService.ServiceError) -> Bool
    ) async throws {
        do {
            _ = try await translate(using: makeService(response: response))
            XCTFail("Expected a translation failure", file: file, line: line)
        } catch let error as OpenAICompatibleTranslationService.ServiceError {
            XCTAssertTrue(matches(error), "Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class TranslationURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (Int, Data))?

    static func setHandler(_ newHandler: ((URLRequest) throws -> (Int, Data))?) {
        lock.lock()
        defer { lock.unlock() }
        handler = newHandler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let handler = try XCTUnwrap(handler)
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
