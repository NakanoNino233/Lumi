import SwiftUI

struct ToolActivityView: View {
    let activity: ToolActivity
    var approve: (UUID, ToolApprovalChoice) -> Void
    var send: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(activity.title, systemImage: activity.status == "pending" ? "hand.raised" : "checklist").font(.headline)
            if activity.status == "pending" {
                Text(activity.reason).font(.callout)
                ToolParameterList(arguments: activity.arguments)
                Text("此操作的结果将提供给 \(activity.destination)。").font(.caption2).foregroundStyle(.secondary)
                ToolApprovalButtons(id: activity.id, approve: approve)
            } else if activity.status == "running" { ProgressView("正在执行…") }
            else { Text(activity.result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if let card = activity.card { NativeCardView(card: card, send: send) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("tool.card.\(activity.name)")
    }
}
struct ToolParameterList: View {
    let arguments: String
    private var rows: [ToolParameter] { ToolParameter.parse(arguments) }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(row.title)).font(.caption2).foregroundStyle(.secondary)
                    Text(row.value).font(.callout).textSelection(.enabled)
                }
            }
        }
    }
}
struct ToolParameter: Identifiable {
    var id: String
    var title: String
    var value: String
    static func parse(_ arguments: String) -> [Self] {
        guard arguments.utf8.count <= 16_000,
              let args = try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8)).object else { return [] }
        let titles = ["date": "提醒时间", "title": "提醒标题", "text": "内容", "category": "记忆分类", "delta": "好感度变化", "mood": "情绪", "sound": "提示音", "name": "技能名称"]
        return ["date", "title", "text", "category", "delta", "mood", "sound", "name"].compactMap { key in
            guard let raw = args[key] else { return nil }
            var value = raw.string ?? raw.encoded
            if key == "date" {
                let clock = ISO8601DateFormatter()
                var date = clock.date(from: value)
                if date == nil { clock.formatOptions.insert(.withFractionalSeconds); date = clock.date(from: value) }
                if let date { value = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocale.current)) }
            }
            if key == "sound" { value = value == "gentle" ? String(localized: "轻柔", locale: AppLocale.current) : String(localized: "清脆", locale: AppLocale.current) }
            if key == "category" {
                let labels = ["preference": "喜好", "fact": "经历", "relationship": "关系", "goal": "计划", "other": "其他"]
                value = labels[value] ?? value
            }
            return Self(id: key, title: titles[key] ?? key, value: value)
        }
    }
}
struct ToolApprovalButtons: View {
    let id: UUID
    var approve: (UUID, ToolApprovalChoice) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        layout {
            Button("仅这次") { approve(id, .once) }.lumiProminentButton().accessibilityIdentifier("tool.once")
            Button("始终允许") { approve(id, .always) }.buttonStyle(.bordered).accessibilityIdentifier("tool.always")
            Button("拒绝", role: .destructive) { approve(id, .deny) }.buttonStyle(.bordered).tint(.red).accessibilityIdentifier("tool.deny")
        }.font(.caption)
    }
}
struct NativeCardView: View {
    let card: NativeCard
    var send: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title).font(.headline)
            ForEach(card.components) { component in NativeCardComponentView(component: component, send: send) }
        }
    }
}
struct NativeCardComponentView: View {
    let component: NativeCard.Component
    var send: (String) -> Void
    @State private var field = ""
    var body: some View {
        switch component.type {
        case "text": Text(component.text).font(.callout).textSelection(.enabled)
        case "button": Button(component.text) { send(component.value ?? component.text) }.buttonStyle(.bordered)
        case "options":
            VStack(alignment: .leading) {
                Text(component.text).font(.subheadline)
                ForEach(component.options ?? [], id: \.self) { option in Button(option) { send(option) }.buttonStyle(.bordered) }
            }
        case "field":
            VStack(alignment: .leading) {
                TextField(component.text, text: $field).textFieldStyle(.roundedBorder).onChange(of: field) { _, value in if value.count > 500 { field = String(value.prefix(500)) } }
                Button("发送填写内容") { send(component.text + "：" + field); field = "" }.disabled(field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        case "progress": ProgressView(component.text, value: component.progress ?? 0, total: 1)
        default: EmptyView()
        }
    }
}
struct ToolPermissionsView: View {
    let provider: ProviderConfig
    @State private var revision = 0
    @AppStorage("tools.maximumCalls", store: AppPreferences.defaults) private var maximum = 4
    var body: some View {
        List {
            Section { Text("授权仅适用于当前接口地址和模型。撤销后，下次操作会再次询问。系统通知、定位和日历权限还可以在 iOS 设置中管理。").font(.caption).foregroundStyle(.secondary) }
            Section { Stepper("每轮最多 \(maximum) 次工具调用", value: $maximum, in: 1...8) }
            Section {
                ForEach(ToolRegistry.specs.filter(\.needsApproval), id: \.name) { spec in
                    HStack { Text(LocalizedStringKey(spec.title)); Spacer(); if ToolPermissions.allowed(name: spec.name, endpoint: provider.endpoint) {
                        Button("撤销") { ToolPermissions.revoke(name: spec.name, endpoint: provider.endpoint); revision += 1 }.accessibilityIdentifier("tool.revoke.\(spec.name)")
                    } else { Text("每次询问").foregroundStyle(.secondary).font(.caption) } }
                }
            }
            Button("撤销所有工具授权", role: .destructive) { ToolPermissions.revokeAll(); revision += 1 }
        }.id(revision).navigationTitle("工具授权").navigationBarTitleDisplayMode(.inline)
    }
}
