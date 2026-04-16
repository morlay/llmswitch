import LLMGateway
import SwiftUI

enum TimeRange: String, CaseIterable {
    case today = "今日"
    case hours24 = "24 小时"
    case days7 = "7 天"
    case days30 = "30 天"

    var since: Date {
        let now = Date()
        switch self {
        case .today: return Calendar.current.startOfDay(for: now)
        case .hours24: return now.addingTimeInterval(-86400)
        case .days7: return now.addingTimeInterval(-7 * 86400)
        case .days30: return now.addingTimeInterval(-30 * 86400)
        }
    }
}

struct UsagePanel: View {
    @ObservedObject var state: AppState
    @State private var summary: TokenUsageSummary?
    @State private var modelUsage: [ModelUsageSummary] = []
    @State private var selectedRange: TimeRange = .today
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 时间范围选择
            HStack {
                Text("统计").font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Button("刷新") { Task { await loadData() } }
            }

            Divider()

            // 总览卡片
            if let s = summary {
                HStack(spacing: 16) {
                    StatCard(title: "总请求", value: "\(s.totalRequests)")
                    StatCard(title: "Prompt Tokens", value: "\(s.totalPromptTokens)")
                    StatCard(title: "Completion Tokens", value: "\(s.totalCompletionTokens)")
                    StatCard(title: "总Tokens", value: "\(s.totalTokens)")
                    StatCard(title: "平均延迟", value: String(format: "%.0fms", s.avgLatencyMs))
                }
            } else {
                Text("加载中...").foregroundStyle(.secondary)
            }

            Divider()

            // 按模型分组
            if !modelUsage.isEmpty {
                Text("按模型").font(.headline)
                ForEach(modelUsage, id: \.model) { m in
                    HStack {
                        Text(m.model).frame(width: 120, alignment: .leading)
                        Text("请求: \(m.totalRequests)").font(.caption).foregroundStyle(.secondary)
                        Text("Prompt: \(m.totalPromptTokens)").font(.caption).foregroundStyle(
                            .secondary)
                        Text("Completion: \(m.totalCompletionTokens)").font(.caption)
                            .foregroundStyle(.secondary)
                        Text("总: \(m.totalTokens)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 400)
        .task { await loadData() }
        .onChange(of: selectedRange) { _, _ in Task { await loadData() } }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        summary = await state.queryUsageSummary(since: selectedRange.since, until: nil)
        modelUsage = await state.queryModelUsage(since: selectedRange.since, until: nil)
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
