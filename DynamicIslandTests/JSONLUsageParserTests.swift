/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should receive a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
@testable import Eave

final class JSONLUsageParserTests: XCTestCase {

    func testChunkBoundariesAndRecordSizeLimit() throws {
        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let record = "{\"timestamp\":\"\(timestamp)\",\"model\":\"test\",\"usage\":{\"input_tokens\":7,\"output_tokens\":3},\"padding\":\"%@\"}"
        // Exact chunk/record boundaries, UTF-8 across reads, oversized records,
        // and a final record without a newline must preserve the same totals.
        let sizes = [65_535, 65_536, 65_537, 1_048_576, 1_048_577, 3_000_000, 200]
        let lines = sizes.map { size -> String in
            let empty = String(format: record, "中")
            return String(format: record, "中" + String(repeating: "x", count: size - empty.utf8.count))
        }
        let file = try makeTempFile(content: lines.joined(separator: "\n"))
        defer { try? FileManager.default.removeItem(at: file) }
        let snapshot = parseFile(file, now: now)
        XCTAssertEqual(snapshot.today.totalTokens, 50)
    }

    func testCodexPublishesQuotaBeforeReadingLogs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexQuotaStub.self]
        let client = CodexQuotaClient(session: URLSession(configuration: configuration), loadCredentials: { ("test", nil) })
        // Exercise protocol dispatch, as used by LLMUsageManager.
        let provider: UsageProvider = CodexUsageProvider(root: directory, quotaClient: client)
        let now = Date()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let update = expectation(description: "Quota published before log scan")
        let result = try await provider.fetchSnapshot(now: now) { snapshot in
            XCTAssertTrue(snapshot.isLocalUsageLoading)
            XCTAssertEqual(snapshot.sessionLimit?.used, 25)
            XCTAssertEqual(snapshot.weekLimit?.used, 60)
            XCTAssertEqual(snapshot.plan, "pro")
            update.fulfill()
            // If scanning happens before this awaited update, the final totals fail.
            let log = """
            {"type":"turn_context","payload":{"model":"test-model"}}
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"output_tokens":5}}}}
            """
            try! Data(log.utf8).write(to: directory.appendingPathComponent("usage.jsonl"))
        }
        await fulfillment(of: [update], timeout: 1)
        XCTAssertFalse(result.isLocalUsageLoading)
        XCTAssertEqual(result.today.totalTokens, 25)
        XCTAssertEqual(result.models.first?.model, "test-model")
        XCTAssertEqual(result.sessionLimit?.used, 25)
        XCTAssertNil(result.localUsageError)

        let missing = CodexUsageProvider(root: directory.appendingPathComponent("missing"), quotaClient: client)
        let quotaOnly = try await missing.fetchSnapshot(now: now)
        XCTAssertFalse(quotaOnly.isLocalUsageLoading)
        XCTAssertEqual(quotaOnly.sessionLimit?.used, 25)
        XCTAssertNotNil(quotaOnly.localUsageError)

        let offlineClient = CodexQuotaClient(loadCredentials: { nil })
        XCTAssertEqual(offlineClient.session.configuration.timeoutIntervalForResource, 20)
        let offline = try await CodexUsageProvider(root: directory, quotaClient: offlineClient).fetchSnapshot(now: now)
        XCTAssertNil(offline.sessionLimit)
        XCTAssertEqual(offline.today.totalTokens, 25)
    }

    private func makeTempFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test_\(UUID().uuidString).jsonl")
        try content.data(using: .utf8)!.write(to: file)
        return file
    }

    private func parseFile(_ file: URL, now: Date) -> UsageSnapshot {
        JSONLUsageParser.aggregate(files: [file], now: now)
    }

    func testParseValidJSONLRecords() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts1 = iso.string(from: now.addingTimeInterval(-3600))
        let ts2 = iso.string(from: now.addingTimeInterval(-7200))

        let content = """
        {"timestamp": "\(ts1)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(ts2)", "message": {"id": "msg2", "model": "claude-3-sonnet", "usage": {"input_tokens": 200, "output_tokens": 100}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testParseDeduplicatesByMessageId() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"timestamp": "\(ts)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(ts)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 100)
        XCTAssertEqual(snapshot.session.outputTokens, 50)
        XCTAssertEqual(snapshot.models.count, 1)
    }

    func testRejectsOversizedUnterminatedRecord() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        // Create a valid record followed by a valid JSON record padded
        // beyond the size limit (with a large dummy field), then a newline
        // and another valid record. The oversized record should be
        // excluded; parsing should resume and process the following record.
        let validRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg1\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}}"
        let padding = String(repeating: "x", count: 1024 * 1024 + 100)
        let oversizedRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msgOversized\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}, \"padding\": \"\(padding)\"}"
        let validRecord2 = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg2\", \"model\": \"claude-3-sonnet\", \"usage\": {\"input_tokens\": 200, \"output_tokens\": 100}}}"
        let content = validRecord + "\n" + oversizedRecord + "\n" + validRecord2

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // msg1 and msg2 should be parsed; the oversized record should be discarded entirely.
        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testParsesAllowedSizeUnterminatedFinalRecord() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        // Create a valid record followed by an allowed-size final line without newline
        let validRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg1\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}}"
        let finalLine = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg2\", \"model\": \"claude-3-sonnet\", \"usage\": {\"input_tokens\": 200, \"output_tokens\": 100}}}"
        let content = validRecord + "\n" + finalLine // No trailing newline

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // Both records should be parsed
        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testSkipsRecordsOutsideWeekWindow() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldTs = iso.string(from: now.addingTimeInterval(-8 * 86400)) // 8 days ago, outside week
        let recentTs = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"timestamp": "\(oldTs)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(recentTs)", "message": {"id": "msg2", "model": "claude-3-sonnet", "usage": {"input_tokens": 200, "output_tokens": 100}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // Only the recent record should be counted
        XCTAssertEqual(snapshot.week.inputTokens, 200)
        XCTAssertEqual(snapshot.week.outputTokens, 100)
    }

    func testParseCodexTokenCountFormat() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"type": "event_msg", "timestamp": "\(ts)", "payload": {"type": "token_count", "info": {"last_token_usage": {"input_tokens": 500, "output_tokens": 250}}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 500)
        XCTAssertEqual(snapshot.session.outputTokens, 250)
        XCTAssertTrue(snapshot.models.contains { $0.model == "codex" })
    }
}

private final class CodexQuotaStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":25},"secondary_window":{"used_percent":60}}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CodexUsageDetailsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2025-03-10T18:00:00Z")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func line(_ type: String, _ payload: [String: Any], at date: Date? = nil) -> String {
        let object: [String: Any] = ["type": type, "timestamp": ISO8601DateFormatter().string(from: date ?? now), "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), encoding: .utf8)! + "\n"
    }
    private func context(_ session: String = "session", project: String = "/one/project", model: String = "known") -> String {
        line("session_meta", ["id": session, "cwd": project]) + line("turn_context", ["model": model, "cwd": project])
    }
    private func modern(_ id: String, at date: Date? = nil, input: Int = 100, output: Int = 20) -> String {
        line("token_usage_record", ["response_id": id, "usage": ["input_tokens": input, "output_tokens": output, "cached_input_tokens": 80]], at: date)
    }
    private func legacy(total: Int = 120, at date: Date? = nil) -> String {
        line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["input_tokens": total - 20, "output_tokens": 20], "last_token_usage": ["input_tokens": 100, "output_tokens": 20, "cached_input_tokens": 80]]], at: date)
    }
    private func temporary(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
    private func store(_ root: URL) -> CodexLogStore {
        CodexLogStore(roots: [root], price: { $0.model == "known" ? Double($0.uncachedInputTokens + $0.outputTokens) / 1000 : nil })
    }

    func testLegacyDedupAndIncrementalIncompleteWrite() throws {
        try temporary { root in
            let file = root.appendingPathComponent("session.jsonl")
            try Data((context() + line("event_msg", ["type": "task_started"]) + legacy() + legacy()).utf8).write(to: file)
            let store = store(root)
            let first = store.snapshot(now: now, calendar: calendar)
            XCTAssertEqual(first.today.totalTokens, 120)
            XCTAssertEqual(first.today.costUSD, 0.04, accuracy: 0.00001)
            XCTAssertEqual(first.codexDetails?.tasks.first?.totals.outputTokens, 20)
            let bytes = store.bytesRead
            _ = store.snapshot(now: now.addingTimeInterval(2), calendar: calendar)
            XCTAssertEqual(store.bytesRead, bytes, "Unchanged history must not be reread")
            let next = legacy(total: 240, at: now.addingTimeInterval(1))
            let split = next.index(next.startIndex, offsetBy: next.count / 2)
            try append(String(next[..<split]), to: file)
            XCTAssertEqual(store.snapshot(now: now.addingTimeInterval(2), calendar: calendar).today.totalTokens, 120)
            try append(String(next[split...]), to: file)
            XCTAssertEqual(store.snapshot(now: now.addingTimeInterval(3), calendar: calendar).today.totalTokens, 240)
            XCTAssertEqual(store.bytesRead - bytes, UInt64(next.utf8.count), "Only appended bytes should be scanned")
            try append(line("event_msg", ["type": "turn_aborted"]), to: file)
            XCTAssertTrue(store.snapshot(now: now.addingTimeInterval(4), calendar: calendar).codexDetails!.tasks.isEmpty)
        }
    }

    func testModernDedupArchiveAndModelSwitch() throws {
        try temporary { root in
            let sessions = root.appendingPathComponent("sessions")
            let archive = root.appendingPathComponent("archived_sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            let log = context() + line("event_msg", ["type": "task_started"]) + modern("one") + modern("one") + legacy()
                + line("turn_context", ["model": "unknown", "cwd": "/two/project"]) + modern("two")
            let file = sessions.appendingPathComponent("one.jsonl")
            try Data(log.utf8).write(to: file)
            try Data(log.utf8).write(to: archive.appendingPathComponent("copy.jsonl"))
            let store = store(root)
            let snapshot = store.snapshot(now: now, calendar: calendar)
            XCTAssertEqual(snapshot.today.totalTokens, 240)
            XCTAssertTrue(snapshot.today.hasUnpricedModel)
            XCTAssertEqual(snapshot.models.count, 2)
            XCTAssertEqual(snapshot.codexDetails?.periods[.today]?.projects.count, 2, "Same basename, distinct project paths")
            XCTAssertEqual(snapshot.codexDetails?.tasks.count, 1)
            try append(line("event_msg", ["type": "task_complete"]), to: file)
            XCTAssertTrue(store.snapshot(now: now, calendar: calendar).codexDetails!.tasks.isEmpty)
            try FileManager.default.removeItem(at: file)
            let archived = store.snapshot(now: now, calendar: calendar, rediscover: true)
            XCTAssertEqual(archived.today.totalTokens, 240)
            XCTAssertTrue(archived.codexDetails!.tasks.isEmpty)
        }
    }

    func testTruncatedReplacedLogsAndOversizedRecords() throws {
        try temporary { root in
            let file = root.appendingPathComponent("one.jsonl")
            try Data((context() + modern("one") + modern("two")).utf8).write(to: file)
            let store = store(root)
            XCTAssertEqual(store.snapshot(now: now, calendar: calendar).today.totalTokens, 240)
            try Data((context() + modern("replacement", input: 20, output: 5)).utf8).write(to: file, options: .atomic)
            XCTAssertEqual(store.snapshot(now: now, calendar: calendar).today.totalTokens, 25)
            try append(String(repeating: "x", count: 1_048_600) + "\n" + modern("three"), to: file)
            XCTAssertEqual(store.snapshot(now: now, calendar: calendar).today.totalTokens, 145)
        }
    }

    func testCalendarPeriodsHeatmapAndDST() throws {
        try temporary { root in
            let today = calendar.startOfDay(for: now)
            let offsets = [0, -1, -2, -6, -7, -29, -30, -90, -91]
            let records = offsets.enumerated().map { index, offset in
                modern("\(index)", at: calendar.date(byAdding: .day, value: offset, to: today)!)
            }.joined()
            try Data((context() + records).utf8).write(to: root.appendingPathComponent("one.jsonl"))
            let store = store(root)
            let snapshot = store.snapshot(now: now, calendar: calendar)
            let details = snapshot.codexDetails!
            XCTAssertEqual(details.days.count, 91)
            XCTAssertEqual(details.total.totalTokens, 8 * 120)
            XCTAssertEqual(snapshot.today.totalTokens, 120)
            XCTAssertEqual(snapshot.week.totalTokens, 4 * 120)
            XCTAssertEqual(details.periods[.month]?.totals.totalTokens, 6 * 120)
            XCTAssertEqual(details.activeDays, 8)
            XCTAssertEqual(details.streak, 3)
            let spring = ISO8601DateFormatter().date(from: "2025-03-09T20:00:00Z")!
            XCTAssertEqual(store.snapshot(now: spring, calendar: calendar).codexDetails?.hours.count, 23)
            let fall = ISO8601DateFormatter().date(from: "2025-11-02T20:00:00Z")!
            XCTAssertEqual(store.snapshot(now: fall, calendar: calendar).codexDetails?.hours.count, 25)
        }
    }

    func testModernMigrationKeepsEarlierHistoryAndEmptyDayStreak() throws {
        try temporary { root in
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            try Data((context() + legacy(at: yesterday) + modern("new")).utf8).write(to: root.appendingPathComponent("one.jsonl"))
            let store = store(root)
            let snapshot = store.snapshot(now: now, calendar: calendar)
            XCTAssertEqual(snapshot.week.totalTokens, 240)
            XCTAssertEqual(snapshot.codexDetails?.streak, 2)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            XCTAssertEqual(store.snapshot(now: tomorrow, calendar: calendar).codexDetails?.streak, 2)
        }
    }

    func testQuotaFailurePreservesLastReadingAndDoesNotBlockLocalRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexDashboardQuotaStub.self]
        let session = URLSession(configuration: configuration)
        let client = CodexQuotaClient(session: session, loadCredentials: { ("test", nil) })
        CodexDashboardQuotaStub.requests = 0
        let provider = CodexUsageProvider(root: directory, quotaClient: client)
        let initial = try await provider.fetchSnapshot(now: now)
        XCTAssertEqual(initial.sessionLimit?.used, 25)
        XCTAssertEqual(initial.plan, "pro")
        XCTAssertEqual(initial.quotaUpdatedAt, now)
        _ = try await provider.fetchSnapshot(now: now.addingTimeInterval(2))
        XCTAssertEqual(CodexDashboardQuotaStub.requests, 1)
        let start = Date()
        let expired = try await provider.fetchSnapshot(now: now.addingTimeInterval(61))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "A slow quota response must not block local updates")
        XCTAssertEqual(expired.sessionLimit?.used, 25)
        XCTAssertTrue(expired.quotaIsStale)
        try await Task.sleep(for: .milliseconds(350))
        let offline = try await provider.fetchSnapshot(now: now.addingTimeInterval(63))
        XCTAssertEqual(offline.sessionLimit?.used, 25)
        XCTAssertEqual(offline.quotaUpdatedAt, initial.quotaUpdatedAt)
        XCTAssertTrue(offline.quotaIsStale)
        XCTAssertEqual(CodexDashboardQuotaStub.requests, 2)
    }

    @MainActor
    func testNavigationResetAndDetailHeight() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let original = coordinator.currentView
        defer { coordinator.currentView = original; coordinator.codexDetailPresented = false }
        coordinator.currentView = .llmUsage
        coordinator.codexDetailPresented = true
        coordinator.currentView = .home
        XCTAssertFalse(coordinator.codexDetailPresented)
        let viewModel = DynamicIslandViewModel()
        coordinator.codexDetailPresented = true
        viewModel.close()
        XCTAssertFalse(coordinator.codexDetailPresented)
        coordinator.codexDetailPresented = true
        viewModel.closeForLockScreen()
        XCTAssertFalse(coordinator.codexDetailPresented)
        let height = codexDetailNotchHeight(headerHeight: 32, screenName: nil)
        XCTAssertLessThanOrEqual(height, 412)
        XCTAssertLessThanOrEqual(height, max(200, (NSScreen.main?.visibleFrame.height ?? 800) - 30))
    }

    @MainActor
    func testInvalidatedRefreshCannotRepublishProgressOrFinalResult() async throws {
        let started = expectation(description: "Refresh started")
        let gate = CodexRefreshGate()
        let provider = DelayedCodexUsageProvider(gate: gate, started: started)
        let manager = LLMUsageManager(providers: [provider])
        manager.refreshAll(force: true)
        await fulfillment(of: [started], timeout: 2)
        manager.discardResult(for: .codex)
        await gate.resume()
        for _ in 0..<100 where manager.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(manager.isRefreshing)
        XCTAssertNil(manager.results[.codex])
    }

    func testLargeHistoryDoesNotReparseUnchangedFiles() throws {
        try temporary { root in
            let log = context() + (0..<5_000).map { modern("response-\($0)") }.joined()
            try Data(log.utf8).write(to: root.appendingPathComponent("history.jsonl"))
            let store = store(root)
            XCTAssertEqual(store.snapshot(now: now, calendar: calendar).today.totalTokens, 600_000)
            let parsed = store.recordsParsed
            let bytes = store.bytesRead
            _ = store.snapshot(now: now.addingTimeInterval(61), calendar: calendar, rediscover: true)
            XCTAssertEqual(store.recordsParsed, parsed)
            XCTAssertEqual(store.bytesRead, bytes)
        }
    }

    func testCustomHomeAndNoLogs() throws {
        let roots = CodexLogStore.defaultRoots(environment: ["CODEX_HOME": "/tmp/custom-codex"])
        XCTAssertEqual(roots.map(\.lastPathComponent), ["sessions", "archived_sessions"])
        XCTAssertTrue(roots.allSatisfy { $0.path.hasPrefix("/tmp/custom-codex/") })
        try temporary { root in
            let snapshot = store(root).snapshot(now: now, calendar: calendar)
            XCTAssertNotNil(snapshot.localUsageError)
            XCTAssertEqual(snapshot.codexDetails?.days.count, 91)
            XCTAssertTrue(snapshot.codexDetails!.tasks.isEmpty)
        }
    }
}

private final class CodexDashboardQuotaStub: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requests: Int {
        get { lock.withLock { count } }
        set { lock.withLock { count = newValue } }
    }
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let number = Self.lock.withLock { Self.count += 1; return Self.count }
        if number == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":25}}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            }
            pending = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    override func stopLoading() { pending?.cancel() }
}

private actor CodexRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

private struct DelayedCodexUsageProvider: UsageProvider {
    let id = ProviderID.codex
    let gate: CodexRefreshGate
    let started: XCTestExpectation
    func fetchSnapshot(now: Date) async throws -> UsageSnapshot { UsageSnapshot() }
    func fetchSnapshot(now: Date, onUpdate: @Sendable (UsageSnapshot) async -> Void) async throws -> UsageSnapshot {
        await gate.wait(started: started)
        let snapshot = UsageSnapshot()
        await onUpdate(snapshot)
        return snapshot
    }
}

final class CodexLogStorePersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_785_000)

    private func fixture(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, root.appendingPathComponent("session.jsonl"), root.appendingPathComponent("cache/usage.plist"))
    }

    private func store(_ root: URL, _ cache: URL?) -> CodexLogStore {
        CodexLogStore(roots: [root], cacheURL: cache, price: { _ in 0 })
    }

    private func record(_ id: String, input: Int = 10) -> String {
        let timestamp = ISO8601DateFormatter().string(from: now)
        return "{\"type\":\"token_usage_record\",\"timestamp\":\"\(timestamp)\",\"payload\":{\"response_id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":2}}}\n"
    }

    private func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testRestartAndAppendMatchFreshScan() throws {
        try fixture { root, file, cache in
            let timestamp = ISO8601DateFormatter().string(from: now)
            let context = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"session\",\"cwd\":\"/project\"}}\n"
                + "{\"type\":\"turn_context\",\"payload\":{\"model\":\"model-a\"}}\n"
                + "{\"type\":\"event_msg\",\"timestamp\":\"\(timestamp)\",\"payload\":{\"type\":\"task_started\"}}\n"
            try Data((context + record("one")).utf8).write(to: file)
            let first = store(root, cache).snapshot(now: now)
            let restored = store(root, cache)
            XCTAssertEqual(restored.snapshot(now: now), first)
            XCTAssertEqual(restored.bytesRead, 0, "An unchanged history must resume without scanning it")
            let added = record("two")
            try append(added, to: file)
            XCTAssertEqual(restored.snapshot(now: now), store(root, nil).snapshot(now: now))
            XCTAssertEqual(restored.bytesRead, UInt64(added.utf8.count))
            XCTAssertEqual(restored.snapshot(now: now).today.totalTokens, 24)
        }
    }

    func testPartialLineIsNotPersistedAndResumes() throws {
        try fixture { root, file, cache in
            let secret = "PRIVATE_CONVERSATION_NOT_FOR_CACHE"
            let partial = "{\"type\":\"response_item\",\"payload\":{\"text\":\"\(secret)"
            try Data((record("one") + partial).utf8).write(to: file)
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 12)
            let archive = try PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil)
            XCTAssertFalse(String(describing: archive).contains(secret))
            let suffix = "\"}}\n" + record("two")
            try append(suffix, to: file)
            let restored = store(root, cache)
            XCTAssertEqual(restored.snapshot(now: now), store(root, nil).snapshot(now: now))
            XCTAssertEqual(restored.bytesRead, UInt64((partial + suffix).utf8.count))
        }
    }

    func testRewrittenBoundaryWithSameMetadataIsDetected() throws {
        try fixture { root, file, cache in
            let padding = "{\"type\":\"response_item\",\"text\":\"" + String(repeating: "x", count: 9000) + "\"}\n"
            try Data((padding + record("one", input: 10)).utf8).write(to: file)
            _ = store(root, cache).snapshot(now: now)
            let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]!
            let handle = try FileHandle(forWritingTo: file)
            try handle.write(contentsOf: Data((padding + record("one", input: 20)).utf8))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
            let restored = store(root, cache)
            XCTAssertEqual(restored.snapshot(now: now).today.totalTokens, 22)
            XCTAssertGreaterThan(restored.bytesRead, 9000)
        }
    }

    func testReplacedTruncatedAndDeletedFiles() throws {
        try fixture { root, file, cache in
            try Data((record("one") + record("two")).utf8).write(to: file)
            _ = store(root, cache).snapshot(now: now)
            try Data(record("new", input: 20).utf8).write(to: file, options: .atomic)
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 22)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 0)
            try handle.close()
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 0)
            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 0)
        }
    }

    func testInvalidCacheFallsBackToLogs() throws {
        try fixture { root, file, cache in
            try Data(record("one").utf8).write(to: file)
            _ = store(root, cache).snapshot(now: now)
            for field in ["version", "build", "roots"] {
                var archive = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: cache), format: nil) as? [String: Any])
                archive[field] = field == "version" ? 999 : "incompatible"
                try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0).write(to: cache)
                let restored = store(root, cache)
                XCTAssertEqual(restored.snapshot(now: now).today.totalTokens, 12)
                XCTAssertGreaterThan(restored.bytesRead, 0)
            }
            try Data("damaged cache".utf8).write(to: cache)
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 12)
        }
    }

    func testFilterHandlesWhitespaceEscapesAndNestedTypes() throws {
        try fixture { root, file, _ in
            let valid = record("one").replacingOccurrences(of: "\"type\":", with: "\"ty\\u0070e\" : ")
            let timestamp = ISO8601DateFormatter().string(from: now)
            let reordered = "{ \"payload\": {\"response_id\":\"two\",\"usage\":{\"input_tokens\":10,\"output_tokens\":2}}, \"timestamp\":\"\(timestamp)\", \"type\" : \"token_usage_record\" }\n"
            let ignored = "{\"type\":\"response_item\",\"payload\":{\"type\":\"token_usage_record\",\"usage\":{\"input_tokens\":999}}}\n"
                + "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"text\":\"\\\"type\\\":\\\"token_count\\\"\"}}\n"
            try Data((ignored + valid + reordered).utf8).write(to: file)
            let parser = store(root, nil)
            XCTAssertEqual(parser.snapshot(now: now).today.totalTokens, 24)
            XCTAssertEqual(parser.recordsParsed, 2)
        }
    }

    func testOversizedPartialAndFinalLineSurviveRestart() throws {
        try fixture { root, file, cache in
            let oversized = String(repeating: "x", count: 1_048_600)
            try Data((record("one") + oversized).utf8).write(to: file)
            _ = store(root, cache).snapshot(now: now)
            try append("remainder\n" + record("two").trimmingCharacters(in: .newlines), to: file)
            XCTAssertEqual(store(root, cache).snapshot(now: now).today.totalTokens, 24)
            let restored = store(root, cache)
            XCTAssertEqual(restored.snapshot(now: now).today.totalTokens, 24)
            XCTAssertEqual(restored.bytesRead, 0)
        }
    }
}
