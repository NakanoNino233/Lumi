import SwiftUI
import SwiftData

enum TokenFunction: String, CaseIterable, Codable, Sendable, Identifiable {
    case chat, group, memory, diary, greeting, friend, connection, meme, safety, moments, unclassified
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .chat: "私聊与工具"
        case .group: "群聊"
        case .memory: "记忆整理"
        case .diary: "日记生成"
        case .greeting: "主动问候"
        case .friend: "生成好友"
        case .connection: "连接测试"
        case .meme: "表情学习"
        case .safety: "安全判断"
        case .moments: "朋友圈"
        case .unclassified: "未分类（旧记录）"
        }
    }
}
@MainActor struct UsagePeriodTotals {
    var today: Int64 = 0
    var month: Int64 = 0
    var categories: [TokenFunction: Int64] = [:]
    init(records: [TokenUsageRecord], now: Date = .now, calendar: Calendar = .current, monthly: Bool = true) {
        let day = calendar.dateInterval(of: .day, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        for record in records where record.hasUsage {
            if let day, record.createdAt >= day.start && record.createdAt < day.end { today = TokenMath.add(today, record.total) }
            if let month, record.createdAt >= month.start && record.createdAt < month.end { self.month = TokenMath.add(self.month, record.total) }
            let interval = monthly ? month : day
            if let interval, record.createdAt >= interval.start && record.createdAt < interval.end {
                categories[record.function] = TokenMath.add(categories[record.function] ?? 0, record.total)
            }
        }
    }
}
struct UsagePeriodSection: View {
    let records: [TokenUsageRecord]
    @AppStorage("usage.dailyLimit", store: AppPreferences.defaults) private var limit = 100_000
    @AppStorage("usage.limitEnabled", store: AppPreferences.defaults) private var enabled = false
    @State private var monthly = true
    var body: some View {
        let totals = UsagePeriodTotals(records: records, monthly: monthly)
        Section("近期用量") {
            LabeledContent("今日 Token", value: totals.today.formatted()).accessibilityIdentifier("tokens.today")
            LabeledContent("本月 Token", value: totals.month.formatted()).accessibilityIdentifier("tokens.month")
            Picker("分类时段", selection: $monthly) { Text("今天").tag(false); Text("本月").tag(true) }.pickerStyle(.segmented)
            ForEach(TokenFunction.allCases) { category in
                if let value = totals.categories[category], value > 0 {
                    VStack(alignment: .leading) {
                        HStack { Text(category.title); Spacer(); Text(value, format: .number).monospacedDigit() }.font(.caption)
                        ProgressView(value: Double(value), total: Double(max(1, monthly ? totals.month : totals.today)))
                    }
                }
            }
        }
        Section {
            Toggle("每日用量提醒", isOn: $enabled)
            if enabled {
                TextField("每日 Token 阈值", value: $limit, format: .number).keyboardType(.numberPad)
                    .onChange(of: limit) { _, new in limit = max(1, min(1_000_000_000, new)) }
            }
        } footer: { Text("达到阈值后，每天在 App 内提醒一次，不阻止继续聊天。根据设备当前时区统计；旧记录保留总量，功能显示为未分类。未返回 usage 的请求不计入。") }
    }
}
struct TokenLimitReminder: ViewModifier {
    func body(content: Content) -> some View {
        content.alert("今日用量提醒", isPresented: Binding(get: { TokenUsageRecorder.shared.limitNotice != nil }, set: { if !$0 { TokenUsageRecorder.shared.limitNotice = nil } })) {
            Button("知道了", role: .cancel) { TokenUsageRecorder.shared.limitNotice = nil }
        } message: { Text(TokenUsageRecorder.shared.limitNotice ?? "") }
    }
}
