import SwiftUI
import WidgetKit
import ActivityKit

struct LumiWidgetEntry: TimelineEntry { var date: Date }
struct LumiWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LumiWidgetEntry { LumiWidgetEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LumiWidgetEntry) -> Void) { completion(LumiWidgetEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LumiWidgetEntry>) -> Void) {
        completion(Timeline(entries: [LumiWidgetEntry(date: .now)], policy: .never))
    }
}
struct LumiStaticWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.lumi.static", provider: LumiWidgetProvider()) { _ in
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image("LumiLogo").resizable().scaledToFill().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12)); Text("Lumi").font(.title2.bold()) }
                Text("慢慢说，我在听。").font(.headline)
                Text("打开 Lumi，看看你的好友。").font(.caption).foregroundStyle(Color.black.opacity(0.65))
            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Color(red: 0.1, green: 0.22, blue: 0.16))
                .containerBackground(Color(red: 0.9, green: 0.95, blue: 0.91), for: .widget)
        }.configurationDisplayName("Lumi 陪伴").description("静态陪伴卡片，不读取聊天资料。").supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct LumiLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LumiActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label(context.attributes.friend, systemImage: "sparkles").font(.headline); Spacer(); Text(context.state.stage).font(.caption) }
                Label("\(context.state.affection)", systemImage: "heart.fill").font(.subheadline)
                if !context.state.latest.isEmpty { Text(context.state.latest).font(.subheadline).lineLimit(2) }
                if let date = context.state.anniversaryDate {
                    HStack { Text(context.state.anniversaryTitle); Spacer(); Text(date, style: .relative) }.font(.caption)
                }
            }.padding(18).activityBackgroundTint(Color(red: 0.9, green: 0.95, blue: 0.91)).activitySystemActionForegroundColor(.black).foregroundStyle(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.friend, systemImage: "sparkles").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Label("\(context.state.affection)", systemImage: "heart.fill").font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        Text(context.state.stage).font(.caption)
                        if !context.state.latest.isEmpty { Text(context.state.latest).font(.caption).lineLimit(1) }
                        if let date = context.state.anniversaryDate { HStack { Text(context.state.anniversaryTitle); Text(date, style: .relative) }.font(.caption2) }
                    }
                }
            } compactLeading: { Image(systemName: "sparkles") } compactTrailing: { Image(systemName: "heart.fill") } minimal: { Image(systemName: "sparkles") }
        }
    }
}
@main struct LumiWidgetBundle: WidgetBundle {
    var body: some Widget { LumiStaticWidget(); LumiLiveWidget() }
}
#Preview(as: .systemSmall) { LumiStaticWidget() } timeline: { LumiWidgetEntry(date: .now) }
