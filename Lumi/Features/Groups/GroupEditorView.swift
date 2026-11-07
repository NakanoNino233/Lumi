import SwiftUI
import SwiftData

struct GroupDraft {
    var name = ""
    var announcement = ""
    var scene = "宿舍夜聊"
    var memberIDs: Set<UUID> = []
    var settings: [GroupMemberSetting] = []
    var relationships: [GroupRelationship] = []
    var independent = false
    var sharesMemory = false
    var automatic = false
    var rounds = 3
    var budget = 60_000
    var notifications = false
    init(group: GroupChat?) {
        guard let group else { return }
        name = group.name; announcement = group.announcement; scene = group.scene; memberIDs = Set(group.memberIDs)
        settings = group.memberSettings; relationships = group.relationships; independent = group.independentReplies
        sharesMemory = group.sharesMemory; automatic = group.automaticChat; rounds = group.automaticRounds; budget = group.automaticBudget; notifications = group.mentionNotifications
    }
}

struct GroupEditorView: View {
    let group: GroupChat?
    var onSave: (GroupChat) -> Void
    var onDelete: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LumiCharacter.createdAt) private var friends: [LumiCharacter]
    @State private var draft: GroupDraft
    @State private var error: String?
    @State private var deleting = false
    init(group: GroupChat? = nil, onSave: @escaping (GroupChat) -> Void, onDelete: @escaping () -> Void = {}) {
        self.group = group; self.onSave = onSave; self.onDelete = onDelete
        _draft = State(initialValue: GroupDraft(group: group))
    }
    private var selected: [LumiCharacter] { friends.filter { draft.memberIDs.contains($0.id) } }
    var body: some View {
        Form {
            GroupIdentityEditor(name: $draft.name, announcement: $draft.announcement, scene: $draft.scene)
            Section {
                ForEach(friends) { friend in
                    Toggle(isOn: Binding(get: { draft.memberIDs.contains(friend.id) }, set: { value in
                        if value { draft.memberIDs.insert(friend.id) } else { draft.memberIDs.remove(friend.id) }
                    })) { HStack { CharacterAvatar(data: friend.avatarData, size: 36); Text(friend.name) } }
                    .disabled(!draft.memberIDs.contains(friend.id) && draft.memberIDs.count >= 6)
                    .accessibilityIdentifier("group.member.\(friend.name)")
                }
            } header: { Text("群成员（\(selected.count)/6）") } footer: { Text("选择 2–6 位好友，推荐 4 位以内。移除成员会保留过去的群消息。") }
            if !selected.isEmpty {
                GroupParticipationEditor(members: selected, settings: $draft.settings)
                GroupRelationshipsEditor(members: selected, relationships: $draft.relationships)
            }
            GroupBehaviorEditor(independent: $draft.independent, sharesMemory: $draft.sharesMemory, automatic: $draft.automatic, rounds: $draft.rounds, budget: $draft.budget, notifications: $draft.notifications, memberCount: selected.count)
            if let group {
                Section {
                    NavigationLink("成员的群聊回忆") { GroupPerspectivesView(group: group) }
                    Button("删除群聊", role: .destructive) { deleting = true }.accessibilityIdentifier("group.delete")
                }
            }
        }
        .navigationTitle(group == nil ? "发起群聊" : "群设置").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(group == nil ? "创建" : "保存") { save() }.accessibilityIdentifier("group.save") }
        }
        .alert("无法保存群聊", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) {} } message: { Text(error ?? "") }
        .alert("删除这个群及其全部群消息？", isPresented: $deleting) {
            Button("删除群聊", role: .destructive) {
                guard let group else { return }
                do { try GroupStore.delete(group, context: context); onDelete(); dismiss() }
                catch { context.rollback(); self.error = LLMError.storage.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("好友与私聊记录会保留，删除后无法恢复。") }
    }
    private func save() {
        do {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try GroupStore.validate(name: name, members: selected)
            guard draft.announcement.count <= 500 else { throw GroupError.format }
            let result = group ?? GroupChat(name: name, memberIDs: selected.map(\.id))
            if group == nil { context.insert(result) }
            result.name = name; result.announcement = draft.announcement; result.scene = draft.scene
            result.memberIDs = selected.map(\.id)
            result.memberSettings = draft.settings.filter { draft.memberIDs.contains($0.characterID) }
            result.relationships = draft.relationships.filter { draft.memberIDs.contains($0.first) && draft.memberIDs.contains($0.second) }.map {
                GroupRelationship(first: $0.first, second: $0.second, text: String($0.text.prefix(100)))
            }
            result.independentReplies = draft.independent; result.sharesMemory = draft.sharesMemory
            result.automaticChat = draft.automatic; result.automaticRounds = draft.rounds; result.automaticBudget = draft.budget; result.mentionNotifications = draft.notifications
            try context.save(); dismiss(); onSave(result)
        } catch { context.rollback(); self.error = (error as? GroupError)?.localizedDescription ?? LLMError.storage.localizedDescription }
    }
}

private struct GroupIdentityEditor: View {
    @Binding var name: String
    @Binding var announcement: String
    @Binding var scene: String
    var body: some View {
        Section("群资料") {
            TextField("群名", text: $name).accessibilityIdentifier("group.name")
            TextField("群公告", text: $announcement, axis: .vertical).lineLimit(2...4)
            Picker("场景", selection: $scene) {
                Text("宿舍夜聊").tag("宿舍夜聊"); Text("班级群").tag("班级群"); Text("开黑群").tag("开黑群"); Text("家庭群").tag("家庭群")
            }
        }
    }
}
private struct GroupParticipationEditor: View {
    let members: [LumiCharacter]
    @Binding var settings: [GroupMemberSetting]
    var body: some View {
        Section("参与程度") {
            ForEach(members) { member in
                Picker(member.name, selection: Binding(get: { settings.first { $0.characterID == member.id }?.participation ?? .normal }, set: { value in
                    settings.removeAll { $0.characterID == member.id }; settings.append(GroupMemberSetting(characterID: member.id, participation: value))
                })) { ForEach(GroupParticipation.allCases, id: \.rawValue) { value in Text(value.title).tag(value) } }
            }
        }
    }
}
private struct GroupRelationshipsEditor: View {
    let members: [LumiCharacter]
    @Binding var relationships: [GroupRelationship]
    private var pairs: [GroupRelationship] {
        members.flatMap { first in members.filter { $0.id.uuidString > first.id.uuidString }.map { GroupRelationship(first: first.id, second: $0.id, text: "") } }
    }
    var body: some View {
        Section {
            ForEach(pairs) { pair in
                VStack(alignment: .leading) {
                    Text("\(members.first { $0.id == pair.first }?.name ?? "") ↔ \(members.first { $0.id == pair.second }?.name ?? "")").font(.caption).foregroundStyle(.secondary)
                    TextField("例如：死党、青梅竹马", text: Binding(get: { relationships.first { $0.id == pair.id }?.text ?? "" }, set: { text in
                        relationships.removeAll { $0.id == pair.id }; relationships.append(GroupRelationship(first: pair.first, second: pair.second, text: text))
                    }))
                }
            }
        } header: { Text("成员之间的关系") } footer: { Text("可选。只用于这个群的互动设定。") }
    }
}
private struct GroupBehaviorEditor: View {
    @Binding var independent: Bool
    @Binding var sharesMemory: Bool
    @Binding var automatic: Bool
    @Binding var rounds: Int
    @Binding var budget: Int
    @Binding var notifications: Bool
    let memberCount: Int
    var body: some View {
        Section {
            Toggle("每位好友独立回复", isOn: $independent).accessibilityIdentifier("group.independent")
            Text(independent ? "每轮约 1–\(max(1, memberCount)) 次请求；输入用量可能为合并模式的数倍，回复更慢。" : "默认每轮合并为 1 次请求，成员按话题选择接话，可连续补充；@ 多位时会全部回应。格式异常会额外重试，最多再逐人请求。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("私聊与群聊记忆互通", isOn: $sharesMemory).accessibilityIdentifier("group.memory")
            Text("默认关闭。开启后，此群可读取成员的私聊事实，成员私聊可读取自己在此群的回忆摘录。关闭后不再传入；已经发送给模型的内容无法收回。").font(.caption).foregroundStyle(.secondary)
        } header: { Text("回复与记忆") }
        Section {
            Toggle("自动闲聊", isOn: $automatic).accessibilityIdentifier("group.automatic")
            if automatic {
                Stepper("最多 \(rounds) 轮", value: $rounds, in: 1...5)
                Stepper("估算用量上限 \(budget) tokens", value: $budget, in: 10_000...100_000, step: 10_000)
            }
            Text("你发送消息后，空闲 8 秒开始。达到轮数或用量上限会停止并提示；离开聊天页面后仍会继续，点击停止可结束。切到系统后台后能否完成取决于系统允许运行的时间。再次发消息会重新开始。用量按文字字节保守预估，并非服务商账单。").font(.caption).foregroundStyle(.secondary)
        } header: { Text("好友之间聊一会儿") }
        Section {
            Toggle("群内 @我 提醒", isOn: $notifications)
            Text("同时需要在设置中开启主动问候与通知权限。仅在 App 不活跃时提醒，共用每日上限及安静时段；不会在后台持续生成群聊。").font(.caption).foregroundStyle(.secondary)
        } header: { Text("通知") }
    }
}

struct GroupPerspectivesView: View {
    let group: GroupChat
    @Query(sort: \GroupPerspective.updatedAt, order: .reverse) private var perspectives: [GroupPerspective]
    @Query private var friends: [LumiCharacter]
    var body: some View {
        List {
            Section { Text("以下是各成员最近参与对话的原文摘录，独立保存在这个群里。").font(.caption).foregroundStyle(.secondary) }
            ForEach(perspectives.filter { $0.groupID == group.id && group.memberIDs.contains($0.characterID) }) { item in
                Section(friends.first { $0.id == item.characterID }?.name ?? "好友") { Text(item.summary).textSelection(.enabled) }
            }
        }.navigationTitle("群聊回忆")
    }
}
