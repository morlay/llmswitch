import Foundation
import SQLite3

// MARK: - 存储错误

public enum UsageStoreError: LocalizedError, Sendable {
    case openFailed(String)
    case migrationFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite 打开失败: \(msg)"
        case .migrationFailed(let msg): return "SQLite 迁移失败: \(msg)"
        case .queryFailed(let msg): return "SQLite 查询失败: \(msg)"
        }
    }
}

// MARK: - Token 用量记录

public struct TokenUsageRecord: Sendable {
    public let id: Int64
    public let timestamp: Date
    public let model: String
    public let provider: String
    public let endpoint: String
    public let statusCode: Int
    public let latencyMs: Int64
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let stream: Bool
    public let errorMessage: String?

    public init(
        id: Int64 = 0,
        timestamp: Date = Date(),
        model: String,
        provider: String,
        endpoint: String,
        statusCode: Int,
        latencyMs: Int64,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        stream: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.provider = provider
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.stream = stream
        self.errorMessage = errorMessage
    }
}

// MARK: - 会话记录（用于 previous_response_id 恢复）

public struct ConversationRecord: Sendable {
    public let id: Int64
    public let responseId: String
    public let previousResponseId: String?
    public let model: String
    public let createdAt: Date
    /// 原始 JSON 数据
    public let data: String

    public init(
        id: Int64 = 0,
        responseId: String,
        previousResponseId: String? = nil,
        model: String,
        createdAt: Date = Date(),
        data: String
    ) {
        self.id = id
        self.responseId = responseId
        self.previousResponseId = previousResponseId
        self.model = model
        self.createdAt = createdAt
        self.data = data
    }
}

// MARK: - 用量汇总

public struct TokenUsageSummary: Sendable {
    public let totalRequests: Int64
    public let totalPromptTokens: Int64
    public let totalCompletionTokens: Int64
    public let totalTokens: Int64
    public let avgLatencyMs: Double
}

public struct ModelUsageSummary: Sendable {
    public let model: String
    public let totalRequests: Int64
    public let totalPromptTokens: Int64
    public let totalCompletionTokens: Int64
    public let totalTokens: Int64
}

public struct ProviderUsageSummary: Sendable {
    public let provider: String
    public let totalRequests: Int64
    public let totalTokens: Int64
}

// MARK: - SQLite 用量存储

public actor GatewayUsageStore {
    private nonisolated(unsafe) var db: OpaquePointer?
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// 打开数据库并执行迁移
    public func open() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = sqlite3_open(url.path, &db)
        guard result == SQLITE_OK, db != nil else {
            let msg = sqlite3_errmsg(db).flatMap { String(cString: $0) } ?? "未知错误"
            throw UsageStoreError.openFailed(msg)
        }

        // 启用 WAL 模式以提升并发性能
        _ = try? execute("PRAGMA journal_mode=WAL")
        _ = try? execute("PRAGMA busy_timeout=5000")

        try migrate()
    }

    /// 关闭数据库
    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Token 用量记录

    /// 记录一次请求的 token 用量
    public func recordUsage(_ record: TokenUsageRecord) throws {
        let sql = """
            INSERT INTO token_usage (timestamp, model, provider, endpoint, status_code, latency_ms, prompt_tokens, completion_tokens, total_tokens, stream, error_message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try execute(
            sql,
            params: [
                .text(ISO8601DateFormatter().string(from: record.timestamp)),
                .text(record.model),
                .text(record.provider),
                .text(record.endpoint),
                .int64(Int64(record.statusCode)),
                .int64(record.latencyMs),
                .int64(Int64(record.promptTokens)),
                .int64(Int64(record.completionTokens)),
                .int64(Int64(record.totalTokens)),
                .int64(record.stream ? 1 : 0),
                .null,
            ])
    }

    /// 更新最近一次请求的 token 用量（用于流式完成后补充）
    public func updateUsageTokens(
        id: Int64, promptTokens: Int, completionTokens: Int, totalTokens: Int
    ) throws {
        let sql = """
            UPDATE token_usage SET prompt_tokens = ?, completion_tokens = ?, total_tokens = ? WHERE id = ?
            """
        try execute(
            sql,
            params: [
                .int64(Int64(promptTokens)),
                .int64(Int64(completionTokens)),
                .int64(Int64(totalTokens)),
                .int64(id),
            ])
    }

    /// 查询 token 用量汇总
    public func queryUsageSummary(since: Date? = nil, until: Date? = nil) throws
        -> TokenUsageSummary
    {
        var conditions: [String] = []
        var params: [SQLParam] = []

        if let since {
            conditions.append("timestamp >= ?")
            params.append(.text(ISO8601DateFormatter().string(from: since)))
        }
        if let until {
            conditions.append("timestamp <= ?")
            params.append(.text(ISO8601DateFormatter().string(from: until)))
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let sql = """
            SELECT COUNT(*), COALESCE(SUM(prompt_tokens), 0), COALESCE(SUM(completion_tokens), 0), COALESCE(SUM(total_tokens), 0), COALESCE(AVG(latency_ms), 0)
            FROM token_usage \(whereClause)
            """

        let rows = try query(sql, params: params)
        guard let row = rows.first, row.count >= 5 else {
            return TokenUsageSummary(
                totalRequests: 0, totalPromptTokens: 0, totalCompletionTokens: 0, totalTokens: 0,
                avgLatencyMs: 0)
        }

        return TokenUsageSummary(
            totalRequests: row[0] as? Int64 ?? 0,
            totalPromptTokens: row[1] as? Int64 ?? 0,
            totalCompletionTokens: row[2] as? Int64 ?? 0,
            totalTokens: row[3] as? Int64 ?? 0,
            avgLatencyMs: row[4] as? Double ?? 0
        )
    }

    /// 按模型分组的用量汇总
    public func queryModelUsage(since: Date? = nil, until: Date? = nil) throws
        -> [ModelUsageSummary]
    {
        var conditions: [String] = []
        var params: [SQLParam] = []

        if let since {
            conditions.append("timestamp >= ?")
            params.append(.text(ISO8601DateFormatter().string(from: since)))
        }
        if let until {
            conditions.append("timestamp <= ?")
            params.append(.text(ISO8601DateFormatter().string(from: until)))
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let sql = """
            SELECT model, COUNT(*), COALESCE(SUM(prompt_tokens), 0), COALESCE(SUM(completion_tokens), 0), COALESCE(SUM(total_tokens), 0)
            FROM token_usage \(whereClause)
            GROUP BY model ORDER BY total_tokens DESC
            """

        let rows = try query(sql, params: params)
        return rows.compactMap { row in
            guard row.count >= 5, let model = row[0] as? String else { return nil }
            return ModelUsageSummary(
                model: model,
                totalRequests: row[1] as? Int64 ?? 0,
                totalPromptTokens: row[2] as? Int64 ?? 0,
                totalCompletionTokens: row[3] as? Int64 ?? 0,
                totalTokens: row[4] as? Int64 ?? 0
            )
        }
    }

    /// 按 provider 分组的用量汇总
    public func queryProviderUsage(since: Date? = nil, until: Date? = nil) throws
        -> [ProviderUsageSummary]
    {
        var conditions: [String] = []
        var params: [SQLParam] = []

        if let since {
            conditions.append("timestamp >= ?")
            params.append(.text(ISO8601DateFormatter().string(from: since)))
        }
        if let until {
            conditions.append("timestamp <= ?")
            params.append(.text(ISO8601DateFormatter().string(from: until)))
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let sql = """
            SELECT provider, COUNT(*), COALESCE(SUM(total_tokens), 0)
            FROM token_usage \(whereClause)
            GROUP BY provider ORDER BY total_tokens DESC
            """

        let rows = try query(sql, params: params)
        return rows.compactMap { row in
            guard row.count >= 3, let provider = row[0] as? String else { return nil }
            return ProviderUsageSummary(
                provider: provider,
                totalRequests: row[1] as? Int64 ?? 0,
                totalTokens: row[2] as? Int64 ?? 0
            )
        }
    }

    // MARK: - 会话历史

    /// 保存一条会话记录
    public func saveConversation(_ record: ConversationRecord) throws {
        let sql = """
            INSERT INTO conversations (response_id, previous_response_id, model, created_at, data)
            VALUES (?, ?, ?, ?, ?)
            """
        try execute(
            sql,
            params: [
                .text(record.responseId),
                .text(record.previousResponseId ?? ""),
                .text(record.model),
                .text(ISO8601DateFormatter().string(from: record.createdAt)),
                .text(record.data),
            ])
    }

    /// 按 response_id 查找会话
    public func findConversation(responseId: String) throws -> ConversationRecord? {
        let sql =
            "SELECT id, response_id, previous_response_id, model, created_at, data FROM conversations WHERE response_id = ?"
        let rows = try query(sql, params: [.text(responseId)])
        guard let row = rows.first, row.count >= 6 else { return nil }

        let prevId = row[2] as? String
        return ConversationRecord(
            id: row[0] as? Int64 ?? 0,
            responseId: row[1] as? String ?? "",
            previousResponseId: (prevId?.isEmpty ?? true) ? nil : prevId,
            model: row[3] as? String ?? "",
            createdAt: Date(),
            data: row[5] as? String ?? ""
        )
    }

    /// 按 previous_response_id 查找后续会话
    public func findConversationsByPrevious(responseId: String) throws -> [ConversationRecord] {
        let sql =
            "SELECT id, response_id, previous_response_id, model, created_at, data FROM conversations WHERE previous_response_id = ? ORDER BY created_at ASC"
        let rows = try query(sql, params: [.text(responseId)])
        return rows.compactMap { row in
            guard row.count >= 6 else { return nil }
            let prevId = row[2] as? String
            return ConversationRecord(
                id: row[0] as? Int64 ?? 0,
                responseId: row[1] as? String ?? "",
                previousResponseId: (prevId?.isEmpty ?? true) ? nil : prevId,
                model: row[3] as? String ?? "",
                createdAt: Date(),
                data: row[5] as? String ?? ""
            )
        }
    }

    /// 查询最近的会话列表
    public func recentConversations(limit: Int = 50) throws -> [ConversationRecord] {
        let sql =
            "SELECT id, response_id, previous_response_id, model, created_at, data FROM conversations ORDER BY created_at DESC LIMIT ?"
        let rows = try query(sql, params: [.int64(Int64(limit))])
        return rows.compactMap { row in
            guard row.count >= 6 else { return nil }
            let prevId = row[2] as? String
            return ConversationRecord(
                id: row[0] as? Int64 ?? 0,
                responseId: row[1] as? String ?? "",
                previousResponseId: (prevId?.isEmpty ?? true) ? nil : prevId,
                model: row[3] as? String ?? "",
                createdAt: Date(),
                data: row[5] as? String ?? ""
            )
        }
    }

    // MARK: - 数据库迁移

    private func migrate() throws {
        let createTokenUsage = """
            CREATE TABLE IF NOT EXISTS token_usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                model TEXT NOT NULL,
                provider TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                status_code INTEGER NOT NULL,
                latency_ms INTEGER NOT NULL DEFAULT 0,
                prompt_tokens INTEGER NOT NULL DEFAULT 0,
                completion_tokens INTEGER NOT NULL DEFAULT 0,
                total_tokens INTEGER NOT NULL DEFAULT 0,
                stream INTEGER NOT NULL DEFAULT 0,
                error_message TEXT
            )
            """

        let createTokenUsageIndex = """
            CREATE INDEX IF NOT EXISTS idx_token_usage_timestamp ON token_usage(timestamp)
            """

        let createTokenUsageModelIndex = """
            CREATE INDEX IF NOT EXISTS idx_token_usage_model ON token_usage(model)
            """

        let createConversations = """
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                response_id TEXT NOT NULL UNIQUE,
                previous_response_id TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL,
                created_at TEXT NOT NULL,
                data TEXT NOT NULL
            )
            """

        let createConversationsIndex = """
            CREATE INDEX IF NOT EXISTS idx_conversations_response_id ON conversations(response_id)
            """

        let createConversationsPrevIndex = """
            CREATE INDEX IF NOT EXISTS idx_conversations_previous ON conversations(previous_response_id)
            """

        let statements = [
            createTokenUsage,
            createTokenUsageIndex,
            createTokenUsageModelIndex,
            createConversations,
            createConversationsIndex,
            createConversationsPrevIndex,
        ]

        for sql in statements {
            try execute(sql)
        }
    }

    // MARK: - SQLite 底层操作

    @discardableResult
    private func execute(_ sql: String, params: [SQLParam] = []) throws -> [String: Any]? {
        guard let db else {
            throw UsageStoreError.queryFailed("数据库未打开")
        }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw UsageStoreError.queryFailed(msg)
        }

        // 绑定参数
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case .null:
                sqlite3_bind_null(stmt, idx)
            case .int64(let value):
                sqlite3_bind_int64(stmt, idx, value)
            case .text(let value):
                sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, nil)
            case .double(let value):
                sqlite3_bind_double(stmt, idx, value)
            }
        }

        // 执行
        let stepResult = sqlite3_step(stmt)
        if stepResult != SQLITE_DONE && stepResult != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw UsageStoreError.queryFailed(msg)
        }

        // 对于 INSERT 返回 last_insert_rowid
        if sql.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("insert") {
            let rowId = sqlite3_last_insert_rowid(db)
            return ["last_insert_rowid": rowId]
        }

        return nil
    }

    /// 执行查询并返回行数据
    private func query(_ sql: String, params: [SQLParam] = []) throws -> [[Any?]] {
        guard let db else {
            throw UsageStoreError.queryFailed("数据库未打开")
        }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw UsageStoreError.queryFailed(msg)
        }

        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case .null:
                sqlite3_bind_null(stmt, idx)
            case .int64(let value):
                sqlite3_bind_int64(stmt, idx, value)
            case .text(let value):
                sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, nil)
            case .double(let value):
                sqlite3_bind_double(stmt, idx, value)
            }
        }

        var rows: [[Any?]] = []
        let columnCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any?] = []
            for i in 0..<columnCount {
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row.append(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row.append(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(stmt, i) {
                        row.append(String(cString: cString))
                    } else {
                        row.append(nil)
                    }
                case SQLITE_NULL:
                    row.append(nil)
                default:
                    if let cString = sqlite3_column_text(stmt, i) {
                        row.append(String(cString: cString))
                    } else {
                        row.append(nil)
                    }
                }
            }
            rows.append(row)
        }

        return rows
    }
}

// MARK: - SQL 参数类型

private enum SQLParam {
    case null
    case int64(Int64)
    case text(String)
    case double(Double)
}
