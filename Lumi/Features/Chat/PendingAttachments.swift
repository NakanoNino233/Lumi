import SwiftUI

struct PendingAttachments: View {
    @Binding var items: [ChatAttachment]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        AttachmentThumbnail(item: item).frame(width: 115, height: 85).clipped()
                        HStack {
                            Text(item.name).font(.caption2).lineLimit(1)
                            Button { items.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("移除附件")
                        }
                        if item.isImage { Text("图片会额外消耗视觉 Token，实际数量以服务商返回为准。").font(.caption2).foregroundStyle(.secondary) }
                        if !item.isImage { Text("发送文字节选").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(12)
        }.background(.bar)
    }
}
