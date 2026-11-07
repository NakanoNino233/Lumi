import SwiftUI

private struct LumiIconOption: Identifiable {
    var id: String
    let title: LocalizedStringResource
    let image: String
    var alternate: String? { id.isEmpty ? nil : id }
    static let all: [Self] = [
        .init(id: "", title: "原版暖光", image: "LumiLogo"),
        .init(id: "AppIconDawn", title: "晨曦", image: "LumiIconDawn"),
        .init(id: "AppIconOcean", title: "海风", image: "LumiIconOcean"),
        .init(id: "AppIconNight", title: "星夜", image: "LumiIconNight")
    ]
}
struct AlternateIconView: View {
    @State private var selected = UIApplication.shared.alternateIconName ?? ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(LumiIconOption.all) { option in
                Button {
                    busy = true; error = nil
                    Task {
                        do { try await UIApplication.shared.setAlternateIconName(option.alternate); selected = option.id }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                } label: {
                    HStack(spacing: 18) {
                        Image(option.image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(option.title).foregroundStyle(.primary)
                        Spacer()
                        if selected == option.id { Image(systemName: "checkmark.circle.fill") }
                    }.padding(.vertical, 5)
                }.disabled(busy || !UIApplication.shared.supportsAlternateIcons)
            }
            if let error { Text(error).foregroundStyle(.orange) }
            Text("保留你提供的原版图标，另有三种配色可选。切换桌面图标时，系统可能显示确认提示。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("桌面图标").navigationBarTitleDisplayMode(.inline)
    }
}
