import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct CharacterCardDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct CharacterEditorTarget: Identifiable {
    let id = UUID()
    var character: LumiCharacter?
}

struct CharacterLibraryView: View {
    var selectedID: UUID?
    var provider: ProviderConfig? = nil
    var showsDone = true
    var onSelect: (LumiCharacter) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LumiCharacter.createdAt) private var characters: [LumiCharacter]
    @Query private var tokenRecords: [TokenUsageRecord]
    @State private var addingFriend = false
    @State private var editor: CharacterEditorTarget?
    @State private var deleting: LumiCharacter?
    @State private var importing = false
    @State private var exporting = false
    @State private var document = CharacterCardDocument(data: Data())
    @State private var exportName = "Lumi-character"
    @State private var error: String?
    var body: some View {
        let tokenSummary = TokenUsageSummary(records: tokenRecords, characters: characters)
        List {
            Section {
                ForEach(characters) { character in
                    CharacterLibraryRow(character: character, tokens: tokenSummary.friends.first { $0.id == character.id }?.total ?? 0, isSelected: character.id == selectedID, onSelect: { onSelect(character) }, onEdit: { editor = CharacterEditorTarget(character: character) }, onExport: { export(character) }, onDelete: { deleting = character })
                }
            } footer: { Text("每个好友拥有独立的聊天、记忆和关系进度。好友卡仅包含设定与图片。") }
            Section {
                Button("添加好友", systemImage: "person.badge.plus") { addingFriend = true }.accessibilityIdentifier("characters.create")
                Button("导入好友卡", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("\(characters.count) 位好友")
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 12)
                    .accessibilityIdentifier("characters.count")
            }
        }
        .navigationTitle("列表")
        .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            ToolbarItem(placement: .topBarTrailing) { Button("添加好友", systemImage: "person.badge.plus") { addingFriend = true }.accessibilityIdentifier("friends.add") } }
        .sheet(isPresented: $addingFriend) { NavigationStack { AddFriendView(provider: provider) { character in addingFriend = false; onSelect(character) } } }
        .sheet(item: $editor) { target in NavigationStack { CharacterEditorView(character: target.character) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 12_000_000 else { throw CharacterCardError.image }
                let card = try CharacterCard.decode(Data(contentsOf: url), existingNames: characters.map(\.name))
                let character = LumiCharacter(name: card.name, isBuiltIn: false); card.apply(to: character)
                context.insert(character)
                do { try context.save() } catch { context.delete(character); throw LLMError.storage }
            } catch { self.error = (error as? CharacterCardError)?.localizedDescription ?? String(localized: "导入失败，请检查 JSON 文件。", locale: AppLocale.current) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportName) { result in
            if case .failure = result { error = String(localized: "导出未完成，请重试。", locale: AppLocale.current) }
        }
        .alert("无法完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("删除好友及其聊天、记忆和关系进度？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                do { MemoryService.shared.cancel(characterID: deleting.id); try CharacterLibrary.remove(deleting, from: context); self.deleting = nil }
                catch { self.error = LLMError.storage.localizedDescription }
            }
        }
    }
    private func export(_ character: LumiCharacter) {
        do { document = CharacterCardDocument(data: try CharacterCard(character).encoded()); exportName = "Lumi-" + character.name; exporting = true }
        catch { self.error = String(localized: "导出未完成，请重试。", locale: AppLocale.current) }
    }
}

private struct CharacterLibraryRow: View {
    let character: LumiCharacter
    let tokens: Int64
    let isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    CharacterAvatar(data: character.avatarData, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(character.name).font(.headline).foregroundStyle(.primary)
                        Text(character.speechStyle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(RelationshipEngine.stageName(character.stageIndex)).font(.caption2).foregroundStyle(theme.accent)
                        TokenRelationshipProgress(total: tokens, compact: true)
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("character.select.\(character.name)")
            Menu {
                NavigationLink { MomentsView(friend: character) } label: { Label("朋友圈", systemImage: "camera.aperture") }
                Button("编辑", systemImage: "pencil", action: onEdit)
                Button("导出好友卡", systemImage: "square.and.arrow.up", action: onExport)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }.foregroundStyle(.secondary).accessibilityLabel("好友操作")
        }.padding(.vertical, 8)
    }
}

struct CharacterEditorView: View {
    let character: LumiCharacter?
    var onCreated: ((LumiCharacter) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var characters: [LumiCharacter]
    @State private var card: CharacterCard
    @State private var avatarPicker: PhotosPickerItem?
    @State private var portraitPicker: PhotosPickerItem?
    @State private var error: String?
    init(character: LumiCharacter?, onCreated: ((LumiCharacter) -> Void)? = nil) {
        self.onCreated = onCreated
        self.character = character
        _card = State(initialValue: character.map(CharacterCard.init) ?? CharacterCard(name: "", personaPrompt: ""))
    }
    var body: some View {
        Form {
            Section("好友名片") {
                HStack(spacing: 18) {
                    CharacterAvatar(data: card.avatar, size: 72)
                    VStack(alignment: .leading) {
                        PhotosPicker("选择头像", selection: $avatarPicker, matching: .images)
                        if card.avatar != nil { Button("移除头像", role: .destructive) { card.avatar = nil } }
                    }
                }
                TextField("名字", text: $card.name).accessibilityIdentifier("character.name")
                PhotosPicker("选择立绘", selection: $portraitPicker, matching: .images)
                if let data = card.portrait, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                    Button("移除立绘", role: .destructive) { card.portrait = nil }
                }
            }
            CharacterTextSection(title: "人设", hint: "描述好友的性格与身份", text: $card.personaPrompt, identifier: "character.persona")
            CharacterTextSection(title: "说话风格", hint: "语气、句子长度与常用表达", text: $card.speechStyle)
            CharacterTextSection(title: "禁忌", hint: "好友应避免的话题或表达", text: $card.taboos)
            CharacterTextSection(title: "背景故事", hint: "好友的经历与日常", text: $card.backgroundStory)
            CharacterTextSection(title: "首次见面开场白", hint: "只在新聊天中显示", text: $card.firstGreeting)
            if let error { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle(character == nil ? "创建好友" : "编辑好友")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).accessibilityIdentifier("character.save") }
        }
        .task(id: avatarPicker) { if let avatarPicker { await load(avatarPicker, avatar: true) } }
        .task(id: portraitPicker) { if let portraitPicker { await load(portraitPicker, avatar: false) } }
    }
    private func load(_ item: PhotosPickerItem, avatar: Bool) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CharacterCardError.image }
            let normalized = try CharacterImage.normalized(data)
            if avatar { card.avatar = normalized } else { card.portrait = normalized }
        } catch { self.error = CharacterCardError.image.localizedDescription }
    }
    private func save() {
        do {
            let names = characters.filter { $0.id != character?.id }.map(\.name)
            let validated = try card.validated(existingNames: names)
            let target = character ?? LumiCharacter(name: validated.name, isBuiltIn: false)
            if character == nil { context.insert(target) }
            let previous = character.map(CharacterCard.init)
            validated.apply(to: target)
            do { try context.save() }
            catch { if let previous { previous.apply(to: target) } else { context.delete(target) }; throw LLMError.storage }
            dismiss(); if character == nil { onCreated?(target) }
        } catch { self.error = error.localizedDescription }
    }
}

struct CharacterTextSection: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    @Binding var text: String
    var identifier = "character.text"
    var body: some View {
        Section { TextField(hint, text: $text, axis: .vertical).lineLimit(3...10).accessibilityIdentifier(identifier) } header: { Text(title) }
    }
}
