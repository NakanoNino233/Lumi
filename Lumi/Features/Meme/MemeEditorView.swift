import SwiftUI
import SwiftData

struct MemeEditorView: View {
    let meme: Meme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var providers: [ProviderConfig]
    @State private var caption = ""
    @State private var keywords = ""
    @State private var mood = ""
    @State private var source = ""
    @State private var license = ""
    @State private var loaded = false
    @State private var data: Data?
    @State private var preview: MemeLearningPreview?
    @State private var error: String?
    @State private var busy = false
    @State private var deleting = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                if let data { MemeImageView(data: data, identity: meme.id).frame(height: 200).frame(maxWidth: .infinity) }
            }
            MemeMetadataFields(caption: $caption, keywords: $keywords, mood: $mood, source: $source, license: $license).disabled(busy)
            Section {
                Button("AI 学习这张图", systemImage: "sparkles", action: prepareLearning).disabled(busy)
                if busy { HStack { ProgressView(); Text("正在整理图片描述…") }; Button("停止") { task?.cancel() } }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            } footer: { Text("可直接手动填写。AI 学图需要已配置的视觉模型；识别结果先填入表单，点击保存才会写入图库。") }
            Section { Button("删除表情", role: .destructive) { deleting = true } }
        }.navigationTitle("编辑表情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(busy).accessibilityIdentifier("memes.save") } }
            .task { guard !loaded else { return }; loaded = true; caption = meme.caption; keywords = meme.keywords; mood = meme.mood; source = meme.source; license = meme.license; data = try? Data(contentsOf: MemeStore.url(meme)) }
            .onDisappear { task?.cancel() }
            .sheet(item: $preview) { item in
                NavigationStack { MemeLearningConfirmation(preview: item, modelName: providers.first.map { $0.modelName + " · " + (URL(string: $0.baseURL)?.host ?? $0.name) } ?? "", onConfirm: { preview = nil; learn(item) }) }
            }
            .confirmationDialog("删除此表情？聊天里已发送的图片仍会保留。", isPresented: $deleting, titleVisibility: .visible) { Button("删除", role: .destructive) { do { try MemeStore.remove(meme, context: context); dismiss() } catch { self.error = error.localizedDescription } } }
    }
    private func prepareLearning() {
        guard let provider = providers.first, provider.supportsVision else { error = AttachmentError.vision.localizedDescription; return }
        guard !((try? KeychainStore().read(for: provider.id)) ?? "").isEmpty else { error = LLMError.missingKey.localizedDescription; return }
        do { guard let data else { throw MemeError.image }; preview = try MemeLearning.preview(data); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func learn(_ preview: MemeLearningPreview) {
        guard let provider = providers.first else { return }
        let endpoint = provider.endpoint; let vision = provider.supportsVision; let id = provider.id
        busy = true; error = nil
        task = Task { @MainActor in
            defer { busy = false }
            do {
                guard let key = try KeychainStore().read(for: id), !key.isEmpty else { throw LLMError.missingKey }
                let result = try await MemeLearning.learn(preview: preview, endpoint: endpoint, supportsVision: vision, key: key)
                try Task.checkCancellation()
                caption = result.caption; keywords = result.keywords.joined(separator: "、"); mood = result.mood
            } catch is CancellationError { } catch { self.error = (error as? MemeError)?.localizedDescription ?? LLMError.sanitized(error).localizedDescription }
        }
    }
    private func save() {
        let values = [caption, keywords, mood, source, license].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !values[0].isEmpty, values.allSatisfy({ $0.count <= 1000 }) else { error = MemeError.metadata.localizedDescription; return }
        let old = [meme.caption, meme.keywords, meme.mood, meme.source, meme.license]
        meme.caption = values[0]; meme.keywords = values[1]; meme.mood = values[2]; meme.source = values[3]; meme.license = values[4]
        do { try context.save(); dismiss() } catch {
            meme.caption = old[0]; meme.keywords = old[1]; meme.mood = old[2]; meme.source = old[3]; meme.license = old[4]
            self.error = MemeError.storage.localizedDescription
        }
    }
}

struct MemeMetadataFields: View {
    @Binding var caption: String
    @Binding var keywords: String
    @Binding var mood: String
    @Binding var source: String
    @Binding var license: String
    var body: some View {
        Section("描述与检索") {
            TextField("描述", text: $caption, axis: .vertical).accessibilityIdentifier("memes.caption")
            TextField("关键词，用逗号分隔", text: $keywords, axis: .vertical)
            TextField("情绪标签", text: $mood)
            Menu("选择常用情绪") { ForEach(MemeMatcher.moods, id: \.self) { value in Button(MemeMoodLabel.title(value)) { mood = value } } }
        }
        Section("来源与许可") { TextField("来源", text: $source, axis: .vertical); TextField("许可", text: $license, axis: .vertical) }
    }
}

struct MemeLearningConfirmation: View {
    let preview: MemeLearningPreview
    let modelName: String
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = UIImage(data: preview.jpeg) { Image(uiImage: image).resizable().scaledToFit() }
                Text("将发送给：\(modelName)").font(.headline)
                Text("共 \(preview.frameCount) 帧，估计约 \(preview.estimatedTokens) tokens（含回复上限）。实际用量与费用以服务商为准。")
                Text("只发送上方预览图，不包含聊天记录。识别结果可在保存前修改。原图仍留在本机。")
                Button("确认发送并识别", action: onConfirm).lumiProminentButton().accessibilityIdentifier("memes.confirmLearning")
            }.padding(24)
        }.navigationTitle("确认 AI 学图").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
