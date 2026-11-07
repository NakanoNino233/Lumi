import SwiftUI
import SwiftData

struct MemoriesView: View {
    let character: LumiCharacter
    let provider: ProviderConfig
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var facts: [MemoryFact]
    @Query private var profiles: [UserProfile]
    @Query private var anniversaries: [Anniversary]
    @Query private var diaries: [DiaryEntry]
    @State private var memoryEditor: MemoryEditorTarget?
    @State private var showAnniversary = false
    @State private var showProfile = false
    @State private var error: String?
    private let service = MemoryService.shared
    init(character: LumiCharacter, provider: ProviderConfig) {
        self.character = character; self.provider = provider
        let id = character.id
        _facts = Query(filter: #Predicate<MemoryFact> { $0.characterID == id }, sort: [SortDescriptor(\MemoryFact.pinOrder, order: .reverse), SortDescriptor(\MemoryFact.importance, order: .reverse), SortDescriptor(\MemoryFact.createdAt, order: .reverse)])
        _profiles = Query(filter: #Predicate<UserProfile> { $0.characterID == id })
        _anniversaries = Query(filter: #Predicate<Anniversary> { $0.characterID == id }, sort: [SortDescriptor(\Anniversary.date)])
        _diaries = Query(filter: #Predicate<DiaryEntry> { $0.characterID == id }, sort: [SortDescriptor(\DiaryEntry.updatedAt, order: .reverse)])
    }
    private var busy: Bool { service.busyCharacterIDs.contains(character.id) }
    var body: some View {
        List {
            Section {
                RelationshipSummary(character: character)
                NavigationLink("关系阶段设置") { RelationshipSettingsView(character: character) }
            }
            Section("陪伴足迹") { FriendTokenProgressLink(character: character) }
            Section("用户档案") {
                Text(profiles.first?.summary.isEmpty == false ? profiles.first!.summary : String(localized: "还没有档案，聊聊你的日常吧。", locale: AppLocale.current)).font(.subheadline).foregroundStyle(.secondary)
                Button("编辑档案") { showProfile = true }
            }
            Section {
                Button("现在整理记忆", systemImage: "sparkles") { schedule(diary: false) }.disabled(busy).accessibilityIdentifier("memory.extract")
                if busy { ProgressView("正在整理…") }
                if let notice = service.notices[character.id] { Text(notice).font(.caption).foregroundStyle(.secondary) }
            } footer: { Text("整理记忆和生成日记会把相关对话发送给你的模型服务商，并产生 API 用量。") }
            Section {
                ForEach(facts) { fact in
                    MemoryFactRow(fact: fact, onEdit: { memoryEditor = MemoryEditorTarget(fact: fact) }, onPin: { fact.isPinned.toggle(); save() }, onDelete: { context.delete(fact); save() })
                }
                Button("添加记忆", systemImage: "plus") { memoryEditor = MemoryEditorTarget() }.accessibilityIdentifier("memory.add")
            } header: { Text("记忆") } footer: { if facts.isEmpty { Text("重要的小事会慢慢留在这里。你也可以手动添加。") } }
            Section("纪念日") {
                ForEach(anniversaries) { item in
                    AnniversaryRow(item: item).swipeActions { Button("删除", role: .destructive) { context.delete(item); save() } }
                }
                Button("添加纪念日", systemImage: "calendar.badge.plus") { showAnniversary = true }
            }
            Section("日记") {
                Button("生成今日日记", systemImage: "book.closed") { schedule(diary: true) }.disabled(busy)
                ForEach(diaries) { diary in
                    NavigationLink { DiaryDetailView(entry: diary) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(diary.dayDate ?? diary.updatedAt, format: .dateTime.month().day()).font(.subheadline.bold())
                            Text(diary.content).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }.padding(.vertical, 4)
                    }.swipeActions { Button("删除", role: .destructive) { context.delete(diary); save() } }
                }
            }
        }
        .navigationTitle("回忆")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(item: $memoryEditor) { target in NavigationStack { MemoryFactEditor(characterID: character.id, fact: target.fact) } }
        .sheet(isPresented: $showAnniversary) { NavigationStack { AnniversaryEditor(characterID: character.id) } }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileEditor(characterID: character.id, profile: profiles.first) } }
        .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func schedule(diary: Bool) { service.schedule(characterID: character.id, provider: provider, container: context.container, force: true, diary: diary, automatic: false) }
    private func save() { do { try context.save() } catch { self.error = LLMError.storage.localizedDescription } }
}

private struct MemoryEditorTarget: Identifiable {
    var id = UUID()
    var fact: MemoryFact?
}
private struct MemoryFactRow: View {
    let fact: MemoryFact
    var onEdit: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MemoryCategory.title(fact.category)).font(.caption).foregroundStyle(theme.accent)
                if fact.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Text("重要度 \(fact.importance)").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(fact.text).font(.subheadline)
        }.padding(.vertical, 6).contentShape(Rectangle()).onTapGesture(perform: onEdit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("memory.fact.\(fact.text)")
            .swipeActions(edge: .leading) { Button(fact.isPinned ? "取消置顶" : "置顶", systemImage: "pin", action: onPin).tint(.orange) }
            .swipeActions { Button("删除", role: .destructive, action: onDelete); Button("编辑", action: onEdit) }
            .contextMenu { Button(fact.isPinned ? "取消置顶" : "置顶", action: onPin); Button("编辑", action: onEdit); Button("删除", role: .destructive, action: onDelete) }
    }
}

enum MemoryCategory {
    static let values = ["生日", "喜好", "经历", "计划", "情绪", "关系", "其他"]
    static func title(_ raw: String) -> LocalizedStringResource {
        switch raw { case "生日": "生日"; case "喜好": "喜好"; case "经历": "经历"; case "计划": "计划"; case "情绪": "情绪"; case "关系": "关系"; default: "其他" }
    }
}

private struct MemoryFactEditor: View {
    let characterID: UUID
    let fact: MemoryFact?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var category: String
    @State private var importance: Int
    @State private var pinned: Bool
    @State private var error: String?
    init(characterID: UUID, fact: MemoryFact?) {
        self.characterID = characterID; self.fact = fact
        _text = State(initialValue: fact?.text ?? ""); _category = State(initialValue: fact?.category ?? "其他")
        _importance = State(initialValue: fact?.importance ?? 3); _pinned = State(initialValue: fact?.isPinned ?? false)
    }
    var body: some View {
        Form {
            Section {
                TextField("值得记住的小事", text: $text, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("memory.text")
                Picker("分类", selection: $category) { ForEach(MemoryCategory.values, id: \.self) { value in Text(MemoryCategory.title(value)).tag(value) } }
                Stepper("重要度 \(importance)", value: $importance, in: 1...5)
                Toggle("置顶", isOn: $pinned)
            }
            if let error { Text(error).foregroundStyle(.orange) }
        }.navigationTitle(fact == nil ? "添加记忆" : "编辑记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard MemoryPayload.validText(clean) else { error = String(localized: "请填写 1–400 字的记忆，避免密码等敏感内容。", locale: AppLocale.current); return }
                    let target = fact ?? MemoryFact(characterID: characterID, category: category, text: clean)
                    if fact == nil { context.insert(target) }
                    target.text = clean; target.category = category; target.importance = importance; target.isPinned = pinned
                    do { try context.save(); dismiss() } catch { self.error = LLMError.storage.localizedDescription }
                }.accessibilityIdentifier("memory.save") }
            }
    }
}

private struct ProfileEditor: View {
    let characterID: UUID
    let profile: UserProfile?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var summary: String
    @State private var error = false
    init(characterID: UUID, profile: UserProfile?) {
        self.characterID = characterID; self.profile = profile; _summary = State(initialValue: profile?.summary ?? "")
    }
    var body: some View {
        Form {
            Section("用户档案") { TextEditor(text: $summary).frame(minHeight: 240) }
            if error { Text("保存失败，请检查长度和内容后重试。").foregroundStyle(.orange) }
        }.navigationTitle("编辑档案").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                guard summary.count <= 2000, !MemoryPayload.sensitive(summary) else { error = true; return }
                let target = profile ?? UserProfile(characterID: characterID)
                if profile == nil { context.insert(target) }
                target.summary = summary; target.updatedAt = .now
                do { try context.save(); dismiss() } catch { self.error = true }
            } }
        }
    }
}

private struct AnniversaryRow: View {
    let item: Anniversary
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                Text(item.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let days = AnniversaryCalendar.daysUntil(item.date, yearly: item.repeatsYearly) {
                Text("还有 \(days) 天").font(.caption).foregroundStyle(theme.accent)
            }
        }
    }
}

enum AnniversaryCalendar {
    static func daysUntil(_ date: Date, yearly: Bool, now: Date = .now, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        var target = calendar.startOfDay(for: date)
        if yearly {
            let parts = calendar.dateComponents([.month, .day], from: date)
            if calendar.dateComponents([.month, .day], from: today) == parts { return 0 }
            guard let next = calendar.nextDate(after: today, matching: parts, matchingPolicy: .nextTime) else { return nil }
            target = next
        }
        return calendar.dateComponents([.day], from: today, to: target).day.map { max(0, $0) }
    }
}
private struct AnniversaryEditor: View {
    let characterID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var yearly = true
    @State private var error = false
    var body: some View {
        Form {
            TextField("纪念日名称", text: $title)
            DatePicker("日期", selection: $date, displayedComponents: .date)
            Toggle("每年纪念", isOn: $yearly)
            if error { Text("保存失败，请重试。").foregroundStyle(.orange) }
        }.navigationTitle("添加纪念日").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                context.insert(Anniversary(characterID: characterID, title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)), date: date, repeatsYearly: yearly))
                do { try context.save(); dismiss() } catch { self.error = true }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
}
private struct DiaryDetailView: View {
    let entry: DiaryEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(entry.day).font(.caption).foregroundStyle(.secondary)
                Text(entry.content).textSelection(.enabled).lineSpacing(8)
                Label("由模型根据对话整理，可在回忆页删除", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.navigationTitle("日记")
    }
}
