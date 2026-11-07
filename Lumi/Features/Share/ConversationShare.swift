import SwiftUI
import UniformTypeIdentifiers

struct SharedChatLine: Codable, Sendable, Identifiable {
    let id: UUID
    let speaker: String
    let role: String
    let text: String
    let date: Date
    let attachments: [ChatAttachment]
    let memes: [SentMeme]
    @MainActor init(_ message: Message, friend: String) {
        id = message.id; speaker = message.role == "user" ? String(localized: "我", locale: AppLocale.current) : friend
        role = message.role; text = message.content; date = message.createdAt
        attachments = message.attachments; memes = message.memes
    }
}
enum ConversationExport {
    static func json(_ lines: [SharedChatLine], title: String) throws -> Data {
        struct Document: Encodable { let version = 1; let title: String; let messages: [SharedChatLine] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(title: title, messages: lines))
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func html(_ lines: [SharedChatLine], title: String) -> Data {
        let rows = lines.map { line in
            let images = line.attachments.filter(\.isImage).map { "<img alt=\"\(escape($0.name))\" src=\"data:image/jpeg;base64,\($0.data.base64EncodedString())\">" }.joined()
            let files = line.attachments.filter { !$0.isImage }.map { "<p>\(escape($0.name))</p><pre>\(escape($0.text))</pre>" }.joined()
            let memes = line.memes.map { "<p>\(escape($0.caption))</p><img alt=\"\" src=\"data:image/png;base64,\($0.data.base64EncodedString())\">" }.joined()
            return "<article class=\"\(line.role == "user" ? "mine" : "friend")\"><strong>\(escape(line.speaker))</strong><time>\(escape(line.date.ISO8601Format()))</time><p>\(escape(line.text))</p>\(images)\(files)\(memes)</article>"
        }.joined(separator: "\n")
        return Data("""
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(escape(title))</title><style>body{font:17px system-ui;max-width:760px;margin:40px auto;padding:16px;background:#f6f7f6;color:#182a24}article{padding:20px;border-radius:18px;margin:16px 0;background:white}.mine{background:#dcece3}p,pre{white-space:pre-wrap;overflow-wrap:anywhere}time{display:block;font-size:12px;color:#53645b}img{max-width:100%;max-height:400px}pre{font:inherit}</style></head>
        <body><h1>\(escape(title))</h1><p>Lumi · AI</p>\(rows)</body></html>
        """.utf8)
    }
}
struct ConversationShareView: View {
    let messages: [Message]
    let friend: String
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    @State private var document = AttachmentDocument(data: Data())
    @State private var type: UTType = .json
    @State private var exporting = false
    @State private var name = "Lumi-Conversation.json"
    @State private var error: String?
    @State private var shareURL: URL?
    private var eligible: [Message] { messages.filter { $0.role != "system" && $0.status != .generating } }
    private var lines: [SharedChatLine] { eligible.filter { selected.contains($0.id) }.map { SharedChatLine($0, friend: friend) } }
    var body: some View {
        List {
            Section {
                Text("只导出选中的对话。内容可能包含隐私，分享前请检查。卡片最多 8 条，每条展示前 500 字；JSON 包含原始附件，HTML 展示图片与文字。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("JSON") { export(.json) }.accessibilityIdentifier("share.json")
                    Spacer()
                    Button("HTML") { export(.html) }.accessibilityIdentifier("share.html")
                    Spacer()
                    Button("图片卡片") { card() }.disabled(selected.count > 8).accessibilityIdentifier("share.card")
                }.disabled(selected.isEmpty)
                if let shareURL { ShareLink(item: shareURL) { Label("分享已生成文件", systemImage: "square.and.arrow.up") } }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            Section("选择对话") {
                ForEach(eligible) { message in
                    Button {
                        if !selected.insert(message.id).inserted { selected.remove(message.id) }
                        clearShare()
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selected.contains(message.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(message.role == "user" ? String(localized: "我", locale: AppLocale.current) : friend).font(.caption).foregroundStyle(.secondary)
                                Text(message.content.isEmpty ? "[附件]" : message.content).lineLimit(4).foregroundStyle(.primary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("分享对话").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onAppear { selected = Set(eligible.suffix(6).map(\.id)) }
        .onDisappear { clearShare() }
        .fileExporter(isPresented: $exporting, document: document, contentType: type, defaultFilename: name) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }
    private func export(_ type: UTType) {
        do {
            let data = type == .json ? try ConversationExport.json(lines, title: friend) : ConversationExport.html(lines, title: friend)
            try prepare(data, type: type, filename: type == .json ? "Lumi-Conversation.json" : "Lumi-Conversation.html")
        } catch { self.error = error.localizedDescription }
    }
    private func card() {
        let renderer = ImageRenderer(content: ConversationCard(lines: lines, friend: friend).environment(\.locale, AppLocale.current))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return }
        do { try prepare(data, type: .png, filename: "Lumi-Card.png") } catch { self.error = error.localizedDescription }
    }
    private func prepare(_ data: Data, type: UTType, filename: String) throws {
        clearShare()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiShare-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename); try data.write(to: url)
        shareURL = url; document = AttachmentDocument(data: data); self.type = type; name = filename; exporting = true
    }
    private func clearShare() { if let shareURL { try? FileManager.default.removeItem(at: shareURL.deletingLastPathComponent()) }; shareURL = nil }
}
struct ConversationCard: View {
    let lines: [SharedChatLine]
    let friend: String
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image("LumiLogo").resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) { Text("Lumi").font(.title2.bold()); Text(friend).font(.caption) }
                Spacer()
                Text("AI").font(.caption.bold()).padding(8).background(.white.opacity(0.7), in: Capsule())
            }
            ForEach(lines.prefix(8)) { line in
                VStack(alignment: .leading, spacing: 6) {
                    Text(line.speaker).font(.caption.bold()).foregroundStyle(Color(red: 0.17, green: 0.39, blue: 0.31))
                    Text(String(line.text.prefix(500)) + (line.text.count > 500 ? "…" : "")).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                    if !line.attachments.isEmpty || !line.memes.isEmpty { Label("包含附件或表情", systemImage: "paperclip").font(.caption) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.role == "user" ? Color(red: 0.83, green: 0.91, blue: 0.86) : .white, in: RoundedRectangle(cornerRadius: 18))
            }
            Text("把这一刻，留在光里。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 390).foregroundStyle(.black).background(Color(red: 0.95, green: 0.96, blue: 0.94)).environment(\.colorScheme, .light)
    }
}
