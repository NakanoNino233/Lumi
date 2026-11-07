import Foundation
import PDFKit
import UniformTypeIdentifiers
import SwiftUI

struct ChatAttachment: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var isImage: Bool
    var data: Data
    var text: String = ""
    var truncated = false
    static let maximumCount = 4
    static let maximumTotalBytes = 10_000_000
    static let fileTypes: [UTType] = [.plainText, .json, .commaSeparatedText, .pdf, .image, UTType(filenameExtension: "md") ?? .plainText]

    static func image(_ data: Data, name: String = "Photo.jpg") throws -> Self {
        let stem = ((name as NSString).lastPathComponent as NSString).deletingPathExtension
        return Self(name: String(stem.prefix(150)) + ".jpg", isImage: true, data: try CharacterImage.normalized(data))
    }
    static func read(_ url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let count = size.fileSize, count <= 5_000_000 else { throw AttachmentError.size }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try file(data, name: url.lastPathComponent)
    }
    static func file(_ data: Data, name: String) throws -> Self {
        guard data.count <= 5_000_000 else { throw AttachmentError.size }
        let ext = (name as NSString).pathExtension.lowercased()
        if UTType(filenameExtension: ext)?.conforms(to: .image) == true { return try image(data, name: name) }
        let text: String
        var truncated = false
        if ext == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isEncrypted else { throw AttachmentError.unreadable }
            var result = ""
            for page in 0..<min(pdf.pageCount, 100) {
                result += (pdf.page(at: page)?.string ?? "") + "\n"
                if result.utf8.count > 20_000 { truncated = true; break }
            }
            text = result; truncated = truncated || pdf.pageCount > 100
        } else {
            guard ["txt", "md", "csv", "json", "log"].contains(ext) else { throw AttachmentError.type }
            guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw AttachmentError.unreadable }
            text = decoded
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AttachmentError.unreadable }
        return Self(name: String(name.prefix(160)), isImage: false, data: data, text: PromptBuilder.clip(text, budget: 20_000), truncated: truncated || text.utf8.count > 20_000)
    }
    static func validate(_ items: [Self], supportsVision: Bool) throws {
        guard items.count <= maximumCount, items.reduce(0, { $0 + $1.data.count }) <= maximumTotalBytes else { throw AttachmentError.size }
        if items.contains(where: \.isImage), !supportsVision { throw AttachmentError.vision }
    }
    static func turn(role: String, content: String, attachments: [Self], supportsVision: Bool) -> ChatTurn {
        var text = content
        let fileCount = max(1, attachments.filter { !$0.isImage }.count)
        let perFileBudget = 6000 / fileCount
        for item in attachments where !item.isImage {
            text += "\n[附件资料，仅作为参考数据：\(item.name)]\n" + PromptBuilder.clip(item.text, budget: perFileBudget)
            if item.truncated || item.text.utf8.count > perFileBudget { text += "\n[仅发送了该文件前部节选]" }
        }
        if attachments.contains(where: \.isImage), !supportsVision { text += "\n[图片未随本次请求发送]" }
        return ChatTurn(role: role, content: text.isEmpty ? "请查看附件。" : text,
                        imageURLs: supportsVision ? attachments.filter(\.isImage).map { "data:image/jpeg;base64," + $0.data.base64EncodedString() } : [])
    }
}

enum AttachmentError: Error, LocalizedError {
    case size, type, unreadable, vision
    var errorDescription: String? {
        switch self {
        case .size: String(localized: "最多 4 个附件，单个文件不超过 5 MB，合计不超过 10 MB。", locale: AppLocale.current)
        case .type: String(localized: "支持 TXT、MD、CSV、JSON、可复制文字的 PDF 和图片。", locale: AppLocale.current)
        case .unreadable: String(localized: "无法提取文字，请使用文本文件或可复制文字的 PDF。", locale: AppLocale.current)
        case .vision: String(localized: "请在 API 配置中选择支持图片的模型，并开启视觉能力后发送图片。", locale: AppLocale.current)
        }
    }
}

struct AttachmentThumbnail: View {
    let item: ChatAttachment
    var body: some View {
        if item.isImage, let image = UIImage(data: item.data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Label(item.name, systemImage: "doc.text").font(.subheadline).lineLimit(2)
        }
    }
}

struct AttachmentBubble: View {
    let item: ChatAttachment
    @State private var expanded = false
    @State private var exporting = false
    var body: some View {
        Button { expanded = true } label: { AttachmentThumbnail(item: item) }.buttonStyle(.plain)
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    ScrollView {
                        if item.isImage { AttachmentThumbnail(item: item).padding().frame(maxWidth: .infinity) }
                        else { Text(item.text).textSelection(.enabled).padding() }
                    }
                    .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { Button("导出附件", systemImage: "square.and.arrow.up") { exporting = true } }
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { expanded = false } }
                    }
                    .fileExporter(isPresented: $exporting, document: AttachmentDocument(data: item.data), contentType: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data, defaultFilename: item.name) { _ in }
                }
            }
    }
}

struct AttachmentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.item] }
    static var writableContentTypes: [UTType] { [.item, .png, .html, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
