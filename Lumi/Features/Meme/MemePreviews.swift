import SwiftUI
import SwiftData

#if DEBUG
private struct MemePreviewHost: View {
    @Environment(\.modelContext) private var context
    @State private var packID: UUID?
    var body: some View {
        NavigationStack { MemePicker { _ in } }
            .task {
                guard packID == nil, let zip = Bundle.main.url(forResource: "Lumi-Starter-Memes", withExtension: "zip"),
                      let prepared = try? MemeArchive.prepare(zip), let pack = try? MemeStore.install(prepared, in: context) else { return }
                packID = pack.id
            }
            .onDisappear { if let packID { try? FileManager.default.removeItem(at: MemeStore.root.appendingPathComponent(packID.uuidString)) } }
    }
}

#Preview("表情 · 浅色") {
    MemePreviewHost().modelContainer(for: LumiSchema.models, inMemory: true)
        .environment(\.locale, Locale(identifier: "zh-Hans")).tint(.lumiAccent).preferredColorScheme(.light)
}
#Preview("表情 · 深色") {
    MemePreviewHost().modelContainer(for: LumiSchema.models, inMemory: true)
        .environment(\.locale, Locale(identifier: "en")).tint(.lumiAccent).preferredColorScheme(.dark)
}
#endif
