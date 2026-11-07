import SwiftUI
import SwiftData

struct TokenUsageView: View {
    @Query private var records: [TokenUsageRecord]
    @Query private var characters: [LumiCharacter]
    var body: some View {
        let summary = TokenUsageSummary(records: records, characters: characters)
        List {
            TokenOverviewSection(summary: summary)
            UsagePeriodSection(records: records)
            Section {
                if summary.friends.isEmpty { ContentUnavailableView("还没有好友", systemImage: "person.2", description: Text("添加好友，留下你们的陪伴足迹。")) }
                ForEach(summary.friends) { friend in
                    NavigationLink { FriendTokenDetailView(id: friend.id, name: friend.name) } label: {
                        TokenRankingRow(friend: friend, rank: (summary.friends.firstIndex { $0.id == friend.id } ?? 0) + 1)
                    }.accessibilityIdentifier("tokens.friend.\(friend.id)")
                }
            } header: { Text("好友消耗排行") } footer: {
                Text("群聊合并请求在本轮发言好友之间均分；独立请求归各自好友。创建好友、连接测试和表情学习计入其他用量。删除好友后仍保留其用量记录。")
            }
            Section {
                LabeledContent("其他用量", value: summary.other.formatted())
                if let date = summary.firstDate { LabeledContent("开始统计") { Text(date, format: .dateTime.year().month().day()) } }
                if summary.unknownRequests > 0 { Text("有 \(summary.unknownRequests) 次请求未返回用量，未计入总量。").font(.caption).foregroundStyle(.secondary) }
                if TokenUsageRecorder.shared.saveFailed { Text("用量保存暂未完成，请检查设备空间。").foregroundStyle(.orange) }
            } footer: { Text("仅累计此版本起服务商实际返回的输入与输出 Token，包含工具续轮、记忆整理、日记和主动问候。缓存命中属于输入的一部分，不重复相加。旧聊天不补算；停止或网络中断可能无法获取用量。此数据不是账单。") }
        }.navigationTitle("Token 用量").accessibilityIdentifier("tokens.screen")
    }
}

private struct TokenOverviewSection: View {
    let summary: TokenUsageSummary
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Token 总消耗量", systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary)
                Text(summary.total, format: .number).font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(theme.accent)
                    .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("tokens.total")
                Text("每一次交流，都留下陪伴的足迹。").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
            LabeledContent("输入 Token", value: summary.input.formatted())
            LabeledContent("输出 Token", value: summary.output.formatted())
            LabeledContent("缓存命中 Token", value: summary.cacheRequests > 0 ? summary.cached.formatted() : String(localized: "尚无缓存数据", locale: AppLocale.current))
            if let rate = summary.cacheRate {
                LabeledContent("输入缓存命中率", value: rate.formatted(.percent.precision(.fractionLength(1))))
                ProgressView(value: rate).tint(theme.accent).accessibilityLabel("输入缓存命中率")
            }
        } header: { Text("累计用量") } footer: {
            Text("已将固定人设与规则前置、动态资料后置，并固定请求数据顺序以提高缓存复用机会。命中率只统计服务商返回缓存数据的输入，实际命中由服务商决定。")
        }
    }
}

private struct TokenRankingRow: View {
    let friend: FriendTokenTotal
    let rank: Int
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(rank, format: .number).font(.system(.headline, design: .rounded)).foregroundStyle(theme.accent).frame(minWidth: 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(friend.name).font(.headline); Spacer(); Text(friend.total, format: .number).font(.subheadline.monospacedDigit()) }
                TokenRelationshipProgress(total: friend.total, compact: true)
            }
        }.padding(.vertical, 5)
    }
}

struct TokenRelationshipProgress: View {
    let total: Int64
    var compact = false
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        let milestone = TokenMilestone.next(for: total)
        VStack(alignment: .leading, spacing: compact ? 5 : 12) {
            if !compact {
                Label("陪伴足迹", systemImage: "heart.text.clipboard").font(.headline)
                Text(total, format: .number).font(.system(.title, design: .rounded).bold()).foregroundStyle(theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.35)
            }
            HStack {
                Text(total >= TokenMilestone.all.last!.target ? "已点亮全部里程碑" : "下一里程碑").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(milestone.title).font(.caption.weight(.medium)).foregroundStyle(theme.accent)
            }
            ProgressView(value: TokenMilestone.progress(for: total)).tint(theme.accent)
                .accessibilityLabel("陪伴 Token 进度")
                .accessibilityValue(TokenMilestone.progress(for: total).formatted(.percent.precision(.fractionLength(2))))
            if !compact {
                Text("\(total.formatted()) / \(milestone.target.formatted()) Token").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("tokens.progress")
    }
}

struct FriendTokenProgressLink: View {
    let character: LumiCharacter
    @Query private var records: [TokenUsageRecord]
    var body: some View {
        let summary = TokenUsageSummary(records: records, characters: [character])
        let total = summary.friends.first { $0.id == character.id }?.total ?? 0
        NavigationLink { FriendTokenDetailView(id: character.id, name: character.name) } label: {
            TokenRelationshipProgress(total: total)
        }.accessibilityIdentifier("friend.tokens")
    }
}

struct FriendTokenDetailView: View {
    let id: UUID
    let name: String
    @Query private var records: [TokenUsageRecord]
    @Query private var characters: [LumiCharacter]
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        let summary = TokenUsageSummary(records: records, characters: characters)
        let friend = summary.friends.first { $0.id == id } ?? FriendTokenTotal(id: id, name: name)
        List {
            Section { TokenRelationshipProgress(total: friend.total).padding(.vertical, 8) }
            Section("你们的里程碑") {
                ForEach(TokenMilestone.all) { milestone in
                    HStack(spacing: 12) {
                        Image(systemName: friend.total >= milestone.target ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(friend.total >= milestone.target ? theme.accent : .secondary)
                        Text(milestone.title)
                        Spacer()
                        if friend.total >= milestone.target { Text("已达成").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }
            }
            Section {
                LabeledContent("输入 Token", value: friend.input.formatted())
                LabeledContent("输出 Token", value: friend.output.formatted())
                LabeledContent("缓存命中 Token", value: friend.cacheRequests > 0 ? friend.cached.formatted() : String(localized: "尚无缓存数据", locale: AppLocale.current))
                if friend.sharedRequests > 0 { Text("包含 \(friend.sharedRequests) 次群聊请求的均分用量。").font(.caption).foregroundStyle(.secondary) }
                if friend.unknownRequests > 0 { Text("有 \(friend.unknownRequests) 次请求未返回用量，未计入总量。").font(.caption).foregroundStyle(.secondary) }
            } header: { Text("用量明细") } footer: { Text("Token 记录你们交流的足迹，不影响已有好感度和关系阶段。") }
        }.navigationTitle(friend.name).navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Token Usage") {
    NavigationStack { TokenUsageView() }
        .modelContainer(TokenPreviewStore.container)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Friend Token Milestones") {
    NavigationStack { FriendTokenDetailView(id: TokenPreviewStore.friendID, name: "小夏") }
        .modelContainer(TokenPreviewStore.container)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Token Usage English") {
    NavigationStack { TokenUsageView() }
        .modelContainer(TokenPreviewStore.container)
        .environment(\.locale, Locale(identifier: "en"))
}

@MainActor private enum TokenPreviewStore {
    static let friendID = UUID()
    static let container: ModelContainer = {
        let container = try! ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let names = ["小夏", "林序", "星野"]
        for (index, name) in names.enumerated() {
            let character = LumiCharacter(name: name, isBuiltIn: false)
            if index == 0 { character.id = friendID }
            container.mainContext.insert(character)
            let record = TokenUsageRecord(id: UUID(), endpoint: ProviderConfig().endpoint.attributed(to: character))
            record.hasUsage = true; record.hasCacheUsage = true
            record.input = [1_200_000_000, 65_000_000, 1_200_000][index]
            record.output = [340_000_000, 21_000_000, 450_000][index]
            record.cached = record.input / 2; container.mainContext.insert(record)
        }
        try! container.mainContext.save(); return container
    }()
}
