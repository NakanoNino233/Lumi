import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var importing = false
    @State private var busy = false
    @State private var prepared: PreparedBackup?
    @State private var exportedURL: URL?
    @State private var notice: String?
    @State private var replacing = false
    @State private var confirm = false
    var body: some View {
        Form {
            Section {
                Button("导出完整备份", systemImage: "square.and.arrow.up") { export() }.accessibilityIdentifier("backup.export")
                Button("选择备份文件", systemImage: "square.and.arrow.down") { importing = true }.accessibilityIdentifier("backup.import")
                if busy { ProgressView() }
                if let exportedURL { ShareLink(item: exportedURL) { Label("保存或分享备份", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("backup.share") }
            } footer: { Text("包含好友、聊天附件、群聊、回忆、朋友圈、图库、技能、市场记录、用量与外观设置。API 密钥和工具授权不导出。备份包含私人内容，请妥善保管。") }
            if let prepared {
                BackupPreviewSection(snapshot: prepared.snapshot)
                Section {
                    Picker("导入方式", selection: $replacing) { Text("合并：保留同 ID 的现有数据").tag(false); Text("覆盖：替换全部应用数据").tag(true) }
                    Button("确认导入", role: replacing ? .destructive : nil) { confirm = true }.accessibilityIdentifier("backup.restore")
                } footer: { Text("合并只增加缺失记录，不修改已有相同 ID。覆盖会删除当前数据库内容。导入后主动问候会关闭，通知需重新设置；模型密钥需单独配置。") }
            }
            if let notice { Section { Text(notice).textSelection(.enabled).accessibilityIdentifier("backup.notice") } }
        }
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            guard let url = try? result.get() else { return }; busy = true; notice = nil
            Task {
                do {
                    let value = try await Task.detached(priority: .userInitiated) { try BackupArchive.prepare(url) }.value
                    prepared?.cleanup(); prepared = value
                } catch { notice = error.localizedDescription }
                busy = false
            }
        }
        .confirmationDialog(replacing ? "覆盖当前全部数据？" : "导入这些数据？", isPresented: $confirm, titleVisibility: .visible) {
            Button(replacing ? "覆盖并导入" : "合并导入", role: replacing ? .destructive : nil) { restore() }
            Button("取消", role: .cancel) { }
        }
        .onDisappear { prepared?.cleanup(); prepared = nil; if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) } }
    }
    private func export() {
        busy = true; notice = nil
        Task {
            do {
                let url = try await BackupArchive.export(context: context)
                if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
                exportedURL = url
            } catch { notice = error.localizedDescription }
            busy = false
        }
    }
    private func restore() {
        guard let prepared else { return }
        do {
            try BackupArchive.restore(prepared, replacing: replacing, container: context.container)
            notice = String(localized: "导入完成。请返回首页查看，通知和模型连接可在设置中重新确认。", locale: AppLocale.current)
            prepared.cleanup(); self.prepared = nil
        } catch { notice = error.localizedDescription }
    }
}
private struct BackupPreviewSection: View {
    let snapshot: LumiBackup
    var body: some View {
        Section("备份预览") {
            LabeledContent("创建时间") { Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute()) }
            LabeledContent("好友", value: snapshot.lumiCharacters.count.formatted())
            LabeledContent("私聊消息", value: snapshot.messages.count.formatted())
            LabeledContent("群聊消息", value: snapshot.groupMessages.count.formatted())
            LabeledContent("记忆", value: snapshot.memoryFacts.count.formatted())
            LabeledContent("表情", value: snapshot.memes.count.formatted())
            LabeledContent("技能", value: snapshot.installedSkills.count.formatted())
            Label("文件与引用校验通过", systemImage: "checkmark.shield")
        }
    }
}
#Preview { NavigationStack { BackupView() }.modelContainer(for: LumiSchema.models, inMemory: true) }
