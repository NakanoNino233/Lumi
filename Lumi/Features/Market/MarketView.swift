import SwiftUI
import SwiftData
import Observation

@MainActor @Observable final class MarketBrowser {
    var source: MarketSource
    var search = "" { didSet { filter() } }
    var kind: MarketKind? { didSet { filter() } }
    private(set) var items: [MarketItem] = []
    private(set) var visible: [MarketItem] = []
    private(set) var loading = false
    private(set) var result: MarketCatalogResult?
    var error: String?
    let loader: MarketCatalogLoader
    private var generation = UUID()
    init(source: MarketSource? = nil) {
        self.source = source ?? Self.savedSource
        let base = AppPreferences.isUITesting ? FileManager.default.temporaryDirectory.appendingPathComponent("LumiUITestMarket") : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LumiMarket")
        loader = MarketCatalogLoader(cacheRoot: base)
    }
    static var savedSource: MarketSource {
        MarketSource(primary: AppPreferences.defaults.string(forKey: "market.primary") ?? "", mirror: AppPreferences.defaults.string(forKey: "market.mirror") ?? "")
    }
    func changeSource(_ new: MarketSource) {
        source = new; result = nil; items = []; filter()
        AppPreferences.defaults.set(new.primary, forKey: "market.primary"); AppPreferences.defaults.set(new.mirror, forKey: "market.mirror")
    }
    func refresh() async {
        let token = UUID(); generation = token; loading = true; error = nil
        do {
            let value = try await loader.load(source: source)
            guard generation == token else { return }
            result = value; items = value.index.items; filter()
        } catch is CancellationError {} catch { if generation == token { self.error = error.localizedDescription } }
        if generation == token { loading = false }
    }
    private func filter() {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = items.filter { (kind == nil || $0.type == kind) && (query.isEmpty || [$0.name, $0.author, $0.summary].contains { $0.localizedCaseInsensitiveContains(query) }) }
    }
}

struct MarketView: View {
    @State private var model = MarketBrowser()
    @State private var editingSource = false
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        @Bindable var browser = model
        List {
            Section {
                MarketHeader(result: model.result, bundled: model.source.primary.isEmpty)
                NavigationLink { MarketInstalledView(source: model.source, available: model.items, loader: model.loader) } label: {
                    Label("已安装与更新", systemImage: "square.stack.3d.up")
                }.accessibilityIdentifier("market.installed")
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        categoryButton(nil, title: String(localized: "全部", locale: AppLocale.current))
                        ForEach(MarketKind.allCases) { kind in categoryButton(kind, title: kind.title) }
                    }.padding(.vertical, 4)
                }.listRowBackground(Color.clear)
                ForEach(model.visible) { item in
                    NavigationLink { MarketDetailView(item: item, source: model.source, loader: model.loader) } label: { MarketItemRow(item: item) }
                        .accessibilityIdentifier("market.item." + item.id)
                }
                if model.visible.isEmpty && !model.loading && model.error == nil { Text("没有匹配的内容").foregroundStyle(.secondary) }
            }
            if model.loading { ProgressView("正在刷新目录…") }
            if let error = model.error {
                Section { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await model.refresh() } } }
            }
        }
        .navigationTitle("内容市场").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $browser.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索名称、作者或简介")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("目录源", systemImage: "server.rack") { editingSource = true }.accessibilityIdentifier("market.sources") } }
        .sheet(isPresented: $editingSource) { NavigationStack { MarketSourceView(source: model.source) { model.changeSource($0) } } }
        .task(id: model.source) { await model.refresh() }
        .refreshable { await model.refresh() }
    }
    private func categoryButton(_ kind: MarketKind?, title: String) -> some View {
        Button { model.kind = kind } label: {
            Text(title).font(.subheadline.weight(model.kind == kind ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(model.kind == kind ? theme.accentForeground : Color.primary)
                .background(model.kind == kind ? theme.accent : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(model.kind == kind ? .isSelected : [])
    }
}
private struct MarketHeader: View {
    let result: MarketCatalogResult?
    let bundled: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("给陪伴添一点新意", systemImage: "bag").font(.title3.bold())
            Text("角色、技能、表情与配色，挑选后先预览再安装。").font(.subheadline).foregroundStyle(.secondary)
            if bundled { Label("内置离线目录", systemImage: "shippingbox").font(.caption).foregroundStyle(.secondary) }
            else if let result {
                Label(LocalizedStringKey(result.cached ? "正在浏览离线缓存" : (result.mirrored ? "已通过备用镜像刷新" : "目录已刷新")), systemImage: result.cached ? "wifi.slash" : "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                Text(result.date, format: .dateTime.year().month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}
struct MarketItemRow: View {
    let item: MarketItem
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.type.icon).font(.title2).foregroundStyle(theme.accent).frame(width: 48, height: 54).background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.headline)
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(item.author + " · v" + item.version + " · " + item.type.title).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}
struct MarketSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var primary: String
    @State private var mirror: String
    @State private var error: String?
    let onSave: (MarketSource) -> Void
    init(source: MarketSource, onSave: @escaping (MarketSource) -> Void) {
        _primary = State(initialValue: source.primary); _mirror = State(initialValue: source.mirror); self.onSave = onSave
    }
    var body: some View {
        Form {
            Section {
                TextField("主目录 index.json 地址", text: $primary).accessibilityIdentifier("market.source.primary")
                TextField("备用镜像 index.json 地址（可选）", text: $mirror).accessibilityIdentifier("market.source.mirror")
            } header: { Text("自定义目录源") } footer: { Text("留空使用内置离线目录。远端地址需为 HTTPS 静态目录，备用镜像应提供同一目录；主地址失败时自动尝试镜像。更换来源后，已安装内容仍会保留。") }
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Section { Button("使用内置目录") { primary = ""; mirror = "" } }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("目录源").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    let source = MarketSource(primary: primary.trimmingCharacters(in: .whitespacesAndNewlines), mirror: mirror.trimmingCharacters(in: .whitespacesAndNewlines))
                    do { try source.validate(); onSave(source); dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("market.source.save") }
            }
    }
}

struct MarketPreview: Sendable {
    var character: CharacterCard?
    var tools: [String] = []
    var skills: [SkillDocument] = []
    var theme: MarketTheme?
    var memeName: String?
    var memeCount = 0
    var thumbnails: [MarketThumbnail] = []
    static func make(data: Data, item: MarketItem) throws -> Self {
        let content = try MarketPackage.inspect(data, item: item); defer { content.cleanup() }
        switch content {
        case .character(let card, let tools): return Self(character: card, tools: tools)
        case .skills(let docs): return Self(skills: docs)
        case .theme(let theme): return Self(theme: theme)
        case .memes(let pack):
            let images = pack.memes.prefix(6).compactMap { item -> MarketThumbnail? in
                guard let data = try? Data(contentsOf: pack.directory.appendingPathComponent(item.path)), let normalized = try? CharacterImage.normalized(data) else { return nil }
                return MarketThumbnail(id: item.path, data: normalized)
            }
            return Self(memeName: pack.name, memeCount: pack.memes.count, thumbnails: images)
        }
    }
}
struct MarketReview: Identifiable {
    let id = UUID()
    var item: MarketItem
    var data: Data
    var preview: MarketPreview
}
struct MarketDetailView: View {
    let item: MarketItem
    let source: MarketSource
    let loader: MarketCatalogLoader
    @Environment(\.modelContext) private var context
    @Query private var installations: [MarketInstallation]
    @State private var working = false
    @State private var error: String?
    @State private var review: MarketReview?
    private var installed: MarketInstallation? { installations.first { $0.id == source.identity + "/" + item.id } }
    private var canUpdate: Bool { installed?.item.map { item.isNewer(than: $0) } ?? false }
    var body: some View {
        List {
            Section { MarketItemRow(item: item); LabeledContent("许可", value: item.license); LabeledContent("下载大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) }
            Section {
                if let version = installed?.item?.version { LabeledContent("已安装版本", value: version) }
                Button(LocalizedStringKey(installed == nil ? "下载并预览" : (canUpdate ? "预览更新" : "已安装"))) { prepare() }
                    .disabled(working || (installed != nil && !canUpdate)).accessibilityIdentifier("market.preview")
                if working { ProgressView("正在校验内容…") }
                if let error { Text(error).foregroundStyle(.red) }
            } footer: { Text("更新会替换内容设定。好友的聊天、记忆、好感度和置顶保持不变；新内容不会自动获得工具授权。") }
            if let address = item.previewURL { Section("内容预览") { MarketRemotePreview(address: address) } }
            Section("文件校验") { Text(item.sha256).font(.caption.monospaced()).textSelection(.enabled); Text(item.downloadURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $review) { value in NavigationStack { MarketInstallReview(review: value, sourceID: source.identity, container: context.container) } }
    }
    private func prepare() {
        working = true; error = nil
        Task {
            do {
                let data = try await loader.download(item, source: source)
                let preview = try await Task.detached(priority: .userInitiated) { try MarketPreview.make(data: data, item: item) }.value
                review = MarketReview(item: item, data: data, preview: preview)
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}
struct MarketInstallReview: View {
    let review: MarketReview
    let sourceID: String
    let container: ModelContainer
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var error: String?
    var body: some View {
        List {
            Section { MarketItemRow(item: review.item); LabeledContent("许可", value: review.item.license) }
            MarketPreviewSections(preview: review.preview)
            Section {
                Text("以下内容仅为设定资料。不能更改安全规则、替你授权或运行代码。安装后，任何工具操作仍遵循你的授权设置。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button("确认安装") {
                    installing = true
                    Task {
                        do { try await MarketInstaller.install(item: review.item, data: review.data, sourceID: sourceID, container: container); dismiss() }
                        catch { self.error = error.localizedDescription }
                        installing = false
                    }
                }.disabled(installing).accessibilityIdentifier("market.confirm")
                if installing { ProgressView("正在安装…") }
            }
        }.navigationTitle("安装前预览").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(installing)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(installing) } }
    }
}
private struct MarketPreviewSections: View {
    let preview: MarketPreview
    var body: some View {
        if let card = preview.character {
            Section("角色设定") {
                CharacterAvatar(data: card.avatar, size: 64)
                Text(card.name).font(.headline); Text(card.personaPrompt)
                if !card.speechStyle.isEmpty { LabeledContent("说话风格", value: card.speechStyle) }
                if !card.backgroundStory.isEmpty { LabeledContent("背景", value: card.backgroundStory) }
                if !card.taboos.isEmpty { LabeledContent("边界", value: card.taboos) }
                if !card.firstGreeting.isEmpty { LabeledContent("初次问候", value: card.firstGreeting) }
            }
            Section("工具声明") { Text(preview.tools.isEmpty ? String(localized: "没有声明工具白名单", locale: AppLocale.current) : preview.tools.map { String(localized: String.LocalizationValue(ToolRegistry.spec($0)?.title ?? $0), locale: AppLocale.current) }.joined(separator: "、")); Text("工具声明仅供查看，不会自动授权。").font(.caption).foregroundStyle(.secondary) }
        }
        ForEach(preview.skills) { skill in
            Section {
                Text(skill.name).font(.headline); Text(skill.description)
                LabeledContent("所需权限", value: skill.permissions.isEmpty ? String(localized: "无", locale: AppLocale.current) : skill.permissions.map(MarketLabels.permission).joined(separator: "、"))
                LabeledContent("工具", value: skill.tools.isEmpty ? String(localized: "无", locale: AppLocale.current) : skill.tools.map { String(localized: String.LocalizationValue(ToolRegistry.spec($0)?.title ?? $0), locale: AppLocale.current) }.joined(separator: "、"))
                Text(skill.body).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let name = preview.memeName { Section("表情包预览") { Text(name).font(.headline); Text("共 \(preview.memeCount) 张表情"); MarketMemePreview(images: preview.thumbnails); Text("安装后可在表情图库管理，已发送的表情会保留。").font(.caption).foregroundStyle(.secondary) } }
        if let theme = preview.theme { Section("聊天预览") { ThemeChatPreview(theme: theme.theme); LabeledContent("字体", value: MarketLabels.font(theme.font)); LabeledContent("气泡样式", value: MarketLabels.bubble(theme.bubbleStyle)) } }
    }
}

struct MarketInstalledView: View {
    let source: MarketSource
    let available: [MarketItem]
    let loader: MarketCatalogLoader
    @Environment(\.modelContext) private var context
    @Query(sort: \MarketInstallation.installedAt, order: .reverse) private var records: [MarketInstallation]
    @State private var pending: MarketInstallation?
    @State private var rollbackPending: MarketInstallation?
    @State private var working = false
    @State private var error: String?
    var body: some View {
        List {
            if records.isEmpty { ContentUnavailableView("还没有安装市场内容", systemImage: "shippingbox") }
            ForEach(records) { record in
                if let item = record.item {
                    Section {
                        MarketItemRow(item: item)
                        if record.sourceID == source.identity, let update = available.first(where: { $0.id == item.id && $0.isNewer(than: item) }) {
                            NavigationLink { MarketDetailView(item: update, source: source, loader: loader) } label: { Label("有新版本，查看更新", systemImage: "arrow.down.circle") }
                        }
                        if let previous = record.previousItem {
                            Button(String(localized: "回滚到 v\(previous.version)", locale: AppLocale.current)) { rollbackPending = record }.accessibilityIdentifier("market.rollback." + item.id)
                        }
                        Button("卸载市场内容", role: .destructive) { pending = record }.accessibilityIdentifier("market.uninstall." + item.id)
                    }
                }
            }
            if working { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }.disabled(working).navigationTitle("已安装与更新").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("卸载这项内容？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let record = pending { Button("确认卸载", role: .destructive) { performUninstall(record.id) } }
                Button("取消", role: .cancel) { pending = nil }
            } message: { Text("角色卡仅解除市场管理，好友与历史全部保留。技能或表情包会从库中移除，已发送内容保留。当前主题未被手动修改时恢复安装前的外观。") }
            .confirmationDialog("回滚到上一版本？", isPresented: Binding(get: { rollbackPending != nil }, set: { if !$0 { rollbackPending = nil } }), titleVisibility: .visible) {
                if let record = rollbackPending { Button("确认回滚") { performRollback(record) } }
                Button("取消", role: .cancel) { rollbackPending = nil }
            } message: { Text("会替换设定内容，聊天、记忆与关系进度保持不变。") }
    }
    private func performUninstall(_ id: String) {
        do { try MarketInstaller.uninstall(id, container: context.container) } catch { self.error = error.localizedDescription }
        pending = nil
    }
    private func performRollback(_ record: MarketInstallation) {
        working = true; error = nil
        Task {
            do { try await MarketInstaller.rollback(record, container: context.container) } catch { self.error = error.localizedDescription }
            working = false; rollbackPending = nil
        }
    }
}

#Preview("Market") {
    NavigationStack { MarketView() }.modelContainer(for: LumiSchema.models, inMemory: true)
}
#Preview("Install theme") {
    let theme = MarketTheme(accent: "7654A5", bubble: "DCCDF5", background: "F3ECFF", font: "rounded", bubbleStyle: "soft")
    let item = MarketItem(id: "demo", type: .theme, name: "暮色鸢尾", author: "Lumi", summary: "柔和的紫色与圆润气泡。", version: "1.0.0", downloadURL: "bundle:demo.json", sha256: String(repeating: "0", count: 64), size: 1, license: "CC0-1.0")
    NavigationStack { List { MarketItemRow(item: item); MarketPreviewSections(preview: MarketPreview(theme: theme)) }.navigationTitle("安装前预览") }
}

private struct MarketMemePreview: View {
    let images: [MarketThumbnail]
    var body: some View {
        ScrollView(.horizontal) {
            HStack { ForEach(images) { thumbnail in
                if let image = UIImage(data: thumbnail.data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 68, height: 68).accessibilityHidden(true) }
            } }
        }
    }
}
private struct MarketRemotePreview: View {
    let address: String
    @State private var data: Data?
    var body: some View {
        VStack {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("内容预览图") }
            else { Label("预览图暂不可用", systemImage: "photo").foregroundStyle(.secondary) }
        }.task(id: address) {
            data = nil
            guard let image = try? await MarketHTTP().fetch(address, limit: 2_000_000), (try? MemeArchive.validateImage(image)) != nil else { return }
            data = image
        }
    }
}

struct MarketThumbnail: Identifiable, Sendable {
    let data: Data
    let id: String
    init(id: String, data: Data) { self.data = data; self.id = id }
}

enum MarketLabels {
    static func permission(_ name: String) -> String {
        let value: String = switch name { case "memory": "记忆"; case "affection": "好感度"; case "notifications": "通知"; case "calendar": "日历"; case "location": "附近位置"; case "audio": "提示音"; default: name }
        return String(localized: String.LocalizationValue(value), locale: AppLocale.current)
    }
    static func font(_ name: String) -> String {
        let value: String = switch name { case "rounded": "圆体"; case "serif": "衬线"; case "monospaced": "等宽"; default: "系统" }
        return String(localized: String.LocalizationValue(value), locale: AppLocale.current)
    }
    static func bubble(_ name: String) -> String {
        let value: String = switch name { case "soft": "柔和"; case "square": "方角"; default: "圆角" }
        return String(localized: String.LocalizationValue(value), locale: AppLocale.current)
    }
}
