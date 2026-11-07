import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MemePicker: View {
    var onSelect: (Meme) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MemePack.createdAt) private var packs: [MemePack]
    @Query(sort: \Meme.caption) private var memes: [Meme]
    @State private var search = ""
    @State private var packFilter = Set<UUID>()
    @State private var moodFilter = Set<String>()
    private var groups: [MemeGroup] {
        packs.filter { $0.enabled && (packFilter.isEmpty || packFilter.contains($0.id)) }.map { pack in
            MemeGroup(id: pack.id, name: pack.name, memes: memes.filter { $0.packID == pack.id && (moodFilter.isEmpty || moodFilter.contains(MemeMatcher.normalizedMood($0.mood))) && (search.isEmpty || ($0.caption + " " + $0.keywords + " " + $0.mood).localizedStandardContains(search)) })
        }.filter { !$0.memes.isEmpty }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.name).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                            ForEach(group.memes) { meme in MemeGridTile(meme: meme) { onSelect(meme); dismiss() } }
                        }
                    }
                }
                if groups.isEmpty { ContentUnavailableView("没有找到表情", systemImage: "face.smiling", description: Text("试试其他关键词，或到图库管理中导入图片。")) }
            }.padding(16)
        }.background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $search, prompt: "搜索表情、关键词")
            .navigationTitle("表情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("图库") { ForEach(packs) { pack in Button { toggle(pack.id, in: &packFilter) } label: { Label(pack.name, systemImage: packFilter.contains(pack.id) ? "checkmark.circle.fill" : "circle") } } }
                        Section("情绪") { ForEach(MemeMatcher.moods, id: \.self) { mood in Button { toggle(mood, in: &moodFilter) } label: { Label(MemeMoodLabel.title(mood), systemImage: moodFilter.contains(mood) ? "checkmark.circle.fill" : "circle") } } }
                        Button("清除筛选") { packFilter = []; moodFilter = [] }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("筛选表情")
                }
                ToolbarItem(placement: .topBarTrailing) { NavigationLink("管理") { MemeLibraryView() } }
            }
    }
    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) { if set.contains(value) { set.remove(value) } else { set.insert(value) } }
}
struct MemeGroup: Identifiable { var id: UUID; var name: String; var memes: [Meme] }

enum MemeMoodLabel {
    static func title(_ mood: String) -> String {
        let titles: [String: LocalizedStringResource] = ["happy": "开心", "shy": "害羞", "sad": "难过", "angry": "生气", "confused": "疑惑", "sigh": "无语", "comfort": "安慰", "like": "喜欢", "sleep": "晚安", "morning": "早安"]
        guard var resource = titles[mood] else { return mood }
        resource.locale = AppLocale.current
        return String(localized: resource)
    }
}

struct MemeLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemePack.createdAt) private var packs: [MemePack]
    @Query private var memes: [Meme]
    @State private var importing = false
    @State private var creating = false
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        List {
            Section {
                NavigationLink("AI 表情设置") { MemeSettingsView() }
                Button("导入图库 ZIP", systemImage: "square.and.arrow.down") { importing = true }.disabled(busy).accessibilityIdentifier("memes.import")
                Button("新建图库", systemImage: "plus") { name = ""; creating = true }.accessibilityIdentifier("memes.create")
                if busy { HStack { ProgressView(); Text("正在校验并导入图库…") } }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            } footer: { Text("支持社区图库和纯图片 ZIP。导入前会检查路径、图片、大小与校验信息；GIF 保留原始动画。") }
            Section("已安装图库") {
                ForEach(packs) { pack in
                    NavigationLink { MemePackDetail(pack: pack) } label: {
                        HStack {
                            Image(systemName: "photo.stack").foregroundStyle(theme.accent).font(.title2).frame(width: 42)
                            VStack(alignment: .leading, spacing: 5) { Text(pack.name); Text("\(memes.filter { $0.packID == pack.id }.count) 张 · \(pack.enabled ? String(localized: "已启用", locale: AppLocale.current) : String(localized: "已停用", locale: AppLocale.current))").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.navigationTitle("表情图库").navigationBarTitleDisplayMode(.inline)
            .alert("新建图库", isPresented: $creating) { TextField("图库名称", text: $name); Button("取消", role: .cancel) { }; Button("创建") { do { _ = try MemeStore.create(name: name, in: context) } catch { self.error = error.localizedDescription } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
                do {
                    let url = try result.get(); busy = true; error = nil
                    task = Task { @MainActor in
                        defer { busy = false }
                        do {
                            let worker = Task.detached { try MemeArchive.prepare(url) }
                            let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                            if Task.isCancelled { try? FileManager.default.removeItem(at: prepared.directory); return }
                            _ = try MemeStore.install(prepared, in: context)
                        } catch is CancellationError { } catch { self.error = (error as? MemeError)?.localizedDescription ?? MemeError.archive.localizedDescription }
                    }
                } catch { if (error as NSError).code != NSUserCancelledError { self.error = MemeError.archive.localizedDescription } }
            }
            .onDisappear { task?.cancel() }
    }
}

struct MemeSettingsView: View {
    @AppStorage("memes.aiEnabled", store: AppPreferences.defaults) private var enabled = true
    @AppStorage("memes.chance", store: AppPreferences.defaults) private var chance = 20
    var body: some View {
        Form {
            Section {
                Toggle("允许 AI 发表情", isOn: $enabled).accessibilityIdentifier("memes.aiEnabled")
                Picker("选图频率", selection: $chance) {
                    Text("从不").tag(0); Text("偶尔 · 20%").tag(20); Text("适中 · 50%").tag(50); Text("经常 · 100%").tag(100)
                }.disabled(!enabled)
            } footer: { Text("只有启用的图库可供选择。AI 每轮最多两张，同一好友至少间隔一分钟；找不到合适图片时保留文字。关闭后不再向模型提供表情说明或工具。") }
            Section("使用说明") {
                Text("点击聊天输入框旁的笑脸可直接发表情；长按图片预览。用户发表情不需要视觉模型，API 尚未配置时也可保存在本机。")
                Text("AI 学图需要视觉模型，会在发送前显示估算用量和确认。图库图片只用于本机表情；启用图库不会自动上传图片。")
            }
        }.navigationTitle("AI 表情设置").navigationBarTitleDisplayMode(.inline)
    }
}

struct MemePackDetail: View {
    let pack: MemePack
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMemes: [Meme]
    @State private var importing = false
    @State private var renaming = false
    @State private var name = ""
    @State private var deleting = false
    @State private var error: String?
    @State private var busy = false
    @State private var export: MemeExportURL?
    private var memes: [Meme] { allMemes.filter { $0.packID == pack.id }.sorted { $0.caption < $1.caption } }
    var body: some View {
        List {
            Section {
                Toggle("启用此图库", isOn: Binding(get: { pack.enabled }, set: { value in let old = pack.enabled; pack.enabled = value; do { try context.save() } catch { pack.enabled = old; self.error = MemeError.storage.localizedDescription } }))
                Button("添加图片", systemImage: "photo.badge.plus") { importing = true }.accessibilityIdentifier("memes.addImage")
                Button("重命名") { name = pack.name; renaming = true }
                Button("导出图库 ZIP", systemImage: "square.and.arrow.up", action: exportPack).disabled(busy || memes.isEmpty)
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            }
            Section("来源与许可") { Text(pack.summary); Text(pack.source).font(.caption); Text(pack.license).font(.caption).foregroundStyle(.secondary) }
            Section("图片") {
                ForEach(memes) { meme in
                    NavigationLink { MemeEditorView(meme: meme) } label: { HStack { Image(systemName: "face.smiling"); VStack(alignment: .leading, spacing: 4) { Text(meme.caption); Text("\(MemeMoodLabel.title(meme.mood)) · 使用 \(meme.usageCount) 次").font(.caption).foregroundStyle(.secondary) } } }.accessibilityIdentifier("meme.edit.\(meme.caption)")
                }
            }
            Section { Button("删除图库", role: .destructive) { deleting = true } }
        }.navigationTitle(pack.name).navigationBarTitleDisplayMode(.inline)
            .alert("重命名图库", isPresented: $renaming) { TextField("图库名称", text: $name); Button("取消", role: .cancel) { }; Button("保存") { let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty, clean.count <= 120 else { error = MemeError.metadata.localizedDescription; return }; let old = pack.name; pack.name = clean; do { try context.save() } catch { pack.name = old; self.error = MemeError.storage.localizedDescription } } }
            .confirmationDialog("删除图库？聊天里已发送的表情仍会保留。", isPresented: $deleting, titleVisibility: .visible) { Button("删除", role: .destructive) { do { try MemeStore.remove(pack, context: context); dismiss() } catch { self.error = error.localizedDescription } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 10_000_000 else { throw MemeError.size }
                    try MemeStore.addImage(Data(contentsOf: url), extension: url.pathExtension, to: pack, context: context)
                } catch { if (error as NSError).code != NSUserCancelledError { self.error = (error as? MemeError)?.localizedDescription ?? MemeError.image.localizedDescription } }
            }
            .sheet(item: $export, onDismiss: { export = nil }) { file in MemeShareSheet(url: file.url).onDisappear { try? FileManager.default.removeItem(at: file.url) } }
    }
    private func exportPack() {
        let snapshots = memes.map { ExportMeme(file: MemeStore.url($0), caption: $0.caption, keywords: $0.keywords, mood: $0.mood, source: $0.source, license: $0.license) }
        let info = (pack.name, pack.summary, pack.license, pack.source); busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { let url = try await Task.detached { try MemeArchive.export(name: info.0, summary: info.1, license: info.2, source: info.3, items: snapshots) }.value; export = MemeExportURL(url: url) }
            catch { self.error = (error as? MemeError)?.localizedDescription ?? MemeError.storage.localizedDescription }
        }
    }
}

struct MemeExportURL: Identifiable { let id = UUID(); var url: URL }
struct MemeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
