import SwiftUI

struct OpenSourceNoticesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("nuwa-skill · 花叔").font(.headline)
                Text("好友生成参考其人物思维框架、表达习惯与诚实边界方法。")
                Link("查看开源项目", destination: URL(string: "https://github.com/alchaincyf/nuwa-skill")!)
                Text(PromptBuilder.resource("NuwaLicense")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text("dsh-meme · yyh-001").font(.headline)
                Text("图库 ZIP 与 SQLite 索引兼容其开放格式；表情检索和发送由 Lumi 原生实现。")
                Link("查看图库格式项目", destination: URL(string: "https://github.com/yyh-001/dsh-meme")!)
                Text(PromptBuilder.resource("DSHMemeLicense")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text("ZIPFoundation · 0.9.20").font(.headline)
                Text(PromptBuilder.resource("ZIPFoundationLicense")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("内置 12 张几何星星表情由 Lumi 原创绘制，采用 CC0-1.0。每张图的来源与许可可在图库内查看。")
            }.padding(24)
        }.navigationTitle("开源致谢").navigationBarTitleDisplayMode(.inline)
    }
}
