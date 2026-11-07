import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InstalledSkill.name) private var skills: [InstalledSkill]
    @State private var tab = 0
    @State private var sortByTokens = false
    @State private var importing = false
    @State private var importingFolder = false
    @State private var loading = false
    @State private var prepared: [SkillDocument] = []
    @State private var error: String?
    private var sorted: [InstalledSkill] { skills.sorted { sortByTokens && $0.document.tokens != $1.document.tokens ? $0.document.tokens > $1.document.tokens : $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                Picker("技能来源", selection: $tab) { Text("已安装").tag(0); Text("示例市场").tag(1) }.pickerStyle(.segmented)
            }
            if tab == 0 {
                Section {
                    Toggle("按正文 token 开销排序", isOn: $sortByTokens)
                    Text("平时仅注入一行简介；挂载或模型调用时才加载正文。token 为本地估算。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(sorted) { skill in
                        SkillInstalledRow(skill: skill) { enabled in
                            let old = skill.enabled; skill.enabled = enabled
                            do { try context.save() } catch { skill.enabled = old; self.error = LLMError.storage.localizedDescription }
                        }
                        .swipeActions { Button("删除", role: .destructive) { remove(skill) } }
                    }
                    if skills.isEmpty { Text("还没有安装技能，可从示例市场选择或导入 SKILL.md。").foregroundStyle(.secondary) }
                }
            } else {
                Section {
                    ForEach(SkillLibrary.examples) { example in
                        SkillExampleRow(document: example, installed: skills.contains { $0.name == example.name }) {
                            do { try SkillLibrary.install([example], in: context) } catch { self.error = error.localizedDescription }
                        }
                    }
                } footer: { Text("这些示例保存在 App 内，离线可安装。技能只包含文字和工具声明。") }
            }
            if loading { ProgressView("正在读取技能…") }
        }.navigationTitle("技能").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu { Button("导入文件或 ZIP") { importing = true }; Button("导入文件夹") { importingFolder = true } } label: { Image(systemName: "plus") }.disabled(loading).accessibilityIdentifier("skills.import")
        } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .zip, UTType(filenameExtension: "md") ?? .plainText]) { read($0) }
        .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { read($0) }
        .sheet(isPresented: Binding(get: { !prepared.isEmpty }, set: { if !$0 { prepared = [] } })) {
            NavigationStack { SkillImportReview(documents: prepared) {
                do { try SkillLibrary.install(prepared, in: context); prepared = [] }
                catch { self.error = error.localizedDescription }
            } }
        }
        .alert("无法完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) {} } message: { Text(error ?? "") }
        .task { do { try SkillLibrary.seed(in: context) } catch { self.error = error.localizedDescription } }
    }
    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get(); loading = true
            Task {
                defer { loading = false }
                do { prepared = try await Task.detached(priority: .userInitiated) { try SkillImport.read(url) }.value }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func remove(_ skill: InstalledSkill) {
        do { try context.save(); context.delete(skill); try context.save() }
        catch { context.rollback(); self.error = LLMError.storage.localizedDescription }
    }
}
struct SkillInstalledRow: View {
    let skill: InstalledSkill
    var onToggle: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { SkillDetailView(document: skill.document) } label: {
                VStack(alignment: .leading, spacing: 5) { Text(skill.name).font(.headline); Text(skill.summary).font(.caption).foregroundStyle(.secondary); Text("正文约 \(skill.document.tokens) token").font(.caption2).foregroundStyle(.secondary) }
            }
            Toggle("启用技能", isOn: Binding(get: { skill.enabled }, set: { value in onToggle(value) })).accessibilityIdentifier("skill.enabled.\(skill.name)")
        }.padding(.vertical, 4)
    }
}
struct SkillExampleRow: View {
    let document: SkillDocument
    let installed: Bool
    var install: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { SkillDetailView(document: document) } label: {
                VStack(alignment: .leading, spacing: 5) { Text(document.name).font(.headline); Text(document.description).font(.caption).foregroundStyle(.secondary) }
            }
            Button(installed ? "已安装" : "安装", action: install).disabled(installed)
        }
    }
}
struct SkillDetailView: View {
    let document: SkillDocument
    var body: some View {
        List {
            Section("简介") { Text(document.description); Text("正文约 \(document.tokens) token").font(.caption).foregroundStyle(.secondary) }
            Section("声明的权限") { Text(document.permissions.isEmpty ? "无需额外权限" : document.permissions.joined(separator: "、")).font(.callout); Text("声明不等于授权。每项操作仍需经过 App 审批和系统权限检查。").font(.caption).foregroundStyle(.secondary) }
            Section("声明的工具") { Text(document.tools.isEmpty ? "无" : document.tools.joined(separator: "、")).font(.caption.monospaced()) }
            Section("技能正文") { Text(document.body).textSelection(.enabled) }
        }.navigationTitle(document.name).navigationBarTitleDisplayMode(.inline)
    }
}
struct SkillImportReview: View {
    let documents: [SkillDocument]
    var install: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section { Text("确认来源与所需权限后安装。技能内容只作为模型参考资料，不能运行代码或自行批准操作。") }
            ForEach(documents) { document in NavigationLink { SkillDetailView(document: document) } label: {
                VStack(alignment: .leading, spacing: 6) { Text(document.name).font(.headline); Text(document.description).font(.caption); Text("正文约 \(document.tokens) token").font(.caption2).foregroundStyle(.secondary); Text(document.permissions.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary) }
            } }
            Button("确认安装", action: install).accessibilityIdentifier("skills.install")
        }.navigationTitle("导入技能").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
struct SkillMountView: View {
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<InstalledSkill> { $0.enabled }, sort: \InstalledSkill.name) private var skills: [InstalledSkill]
    private var tokens: Int { skills.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.document.tokens } }
    var body: some View {
        List {
            Section {
                Text("本条消息挂载正文约 \(tokens) token，上限 6000。未挂载的已启用技能仍可按需加载。").font(.caption).foregroundStyle(.secondary)
                ForEach(skills) { skill in
                    Button { if selection.contains(skill.id) { selection.remove(skill.id) } else { selection.insert(skill.id) } } label: {
                        HStack { VStack(alignment: .leading) { Text(skill.name); Text("约 \(skill.document.tokens) token").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selection.contains(skill.id) { Image(systemName: "checkmark.circle.fill") } }
                    }.accessibilityIdentifier("skill.mount.\(skill.name)")
                }
            }
            NavigationLink("管理技能") { SkillLibraryView() }
        }.navigationTitle("挂载技能").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(tokens > 6000) } }
        .interactiveDismissDisabled(tokens > 6000)
    }
}

struct MountedSkillsBar: View {
    @Binding var selection: Set<UUID>
    @Query private var skills: [InstalledSkill]
    private var mounted: [InstalledSkill] { skills.filter { $0.enabled && selection.contains($0.id) }.sorted { $0.name < $1.name } }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(mounted) { skill in
                    Button { selection.remove(skill.id) } label: { Label(skill.name, systemImage: "xmark.circle.fill").font(.caption).padding(8).background(.quaternary, in: Capsule()) }
                }
            }.padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}
