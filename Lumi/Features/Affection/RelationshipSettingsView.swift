import SwiftUI
import SwiftData

struct RelationshipSummary: View {
    let character: LumiCharacter
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CharacterAvatar(data: character.avatarData, size: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(character.name).font(.title3.bold())
                    Text(RelationshipEngine.stageName(character.stageIndex)).font(.subheadline).foregroundStyle(theme.accent)
                }
                Spacer()
                Text("\(character.affection) / 100").font(.system(.title3, design: .rounded).bold()).foregroundStyle(theme.accent)
            }
            ProgressView(value: Double(character.affection), total: 100).tint(theme.accent)
            if let data = character.portraitData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }.padding(.vertical, 8)
    }
}

struct RelationshipSettingsView: View {
    let character: LumiCharacter
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var familiar: Int
    @State private var close: Int
    @State private var partner: Int
    @State private var error = false
    init(character: LumiCharacter) {
        self.character = character; _familiar = State(initialValue: character.familiarThreshold)
        _close = State(initialValue: character.closeThreshold); _partner = State(initialValue: character.partnerThreshold)
    }
    var body: some View {
        Form {
            Section { RelationshipSummary(character: character) }
            Section("陪伴足迹") { FriendTokenProgressLink(character: character) }
            Section {
                Stepper("熟悉：\(familiar)", value: $familiar, in: 1...97)
                Stepper("暧昧：\(close)", value: $close, in: 2...98)
                Stepper("恋人：\(partner)", value: $partner, in: 3...100)
            } header: { Text("阶段阈值") } footer: { Text("阈值须按熟悉、暧昧、恋人递增。关系初始为陌生。模型每轮最多改变 3 点，每天最多增加或减少 6 点；重复发送和重新生成不会重复加分。") }
            if error { Text("请确保阈值递增，并重试保存。").foregroundStyle(.orange) }
        }.navigationTitle("关系阶段设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") {
                guard familiar < close, close < partner else { error = true; return }
                character.familiarThreshold = familiar; character.closeThreshold = close; character.partnerThreshold = partner
                let next = RelationshipEngine.stage(character.affection, character: character)
                if next != character.stageIndex {
                    character.stageIndex = next
                    let cid = character.id
                    if let conversation = try? context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == cid })).first {
                        let stage = RelationshipEngine.stageText(next)
                        context.insert(Message(conversationID: conversation.id, role: "system", content: String(localized: "关系进入新阶段：\(stage)", locale: AppLocale.current)))
                    }
                }
                do { try context.save(); dismiss() } catch { self.error = true }
            } } }
    }
}
