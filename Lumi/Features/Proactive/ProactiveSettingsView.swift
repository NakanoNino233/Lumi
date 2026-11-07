import SwiftUI
import SwiftData
import UserNotifications

struct ProactiveSettingsView: View {
    @Query(sort: \LumiCharacter.createdAt) private var characters: [LumiCharacter]
    @AppStorage("proactive.enabled", store: AppPreferences.defaults) private var enabled = false
    @AppStorage("proactive.limit", store: AppPreferences.defaults) private var dailyLimit = 1
    @AppStorage("proactive.quietStart", store: AppPreferences.defaults) private var quietStart = 22
    @AppStorage("proactive.quietEnd", store: AppPreferences.defaults) private var quietEnd = 8
    @AppStorage("proactive.character", store: AppPreferences.defaults) private var characterID = ""
    @AppStorage("context.weather", store: AppPreferences.defaults) private var weather = false
    @AppStorage("context.calendar", store: AppPreferences.defaults) private var calendar = false
    @AppStorage("context.battery", store: AppPreferences.defaults) private var battery = false
    @State private var hasPermission = false
    @State private var permissionBusy = false
    @State private var contextService = ContextService.shared
    private let service = ProactiveService.shared
    private var preferences: CompanionPreferences { CompanionPreferences(enabled: enabled, dailyLimit: dailyLimit, quietStart: quietStart, quietEnd: quietEnd, weather: weather, calendar: calendar, battery: battery, characterID: characterID) }
    var body: some View {
        Form {
            Section {
                Toggle("主动问候", isOn: $enabled).accessibilityIdentifier("proactive.enabled")
                Picker("问候好友", selection: $characterID) {
                    Text("当前聊天好友").tag("")
                    ForEach(characters) { character in Text(character.name).tag(character.id.uuidString) }
                }
                Stepper("每天最多 \(dailyLimit) 条", value: $dailyLimit, in: 1...2)
                HStack {
                    Picker("安静开始", selection: $quietStart) { ForEach(0..<24) { hour in Text("\(hour):00").tag(hour) } }
                    Picker("安静结束", selection: $quietEnd) { ForEach(0..<24) { hour in Text("\(hour):00").tag(hour) } }
                }
                Text("开始与结束相同时表示全天均可通知。时间会自然浮动约 15 分钟，多日未回应会自动减少问候。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("今天已发 \(service?.todayCount ?? 0) 条").font(.callout)
            } header: { Text("问候节奏") } footer: {
                Text("开启后，Lumi 会将好友设定、关系、档案及近期记忆发给你配置的模型，预先准备约一周问候。到点通知由本机发送；问候用尽前会留下一句温和收尾。统计按通知到点计算，系统专注模式可能延迟显示。")
            }
            Section {
                if hasPermission { Label("已允许通知", systemImage: "checkmark.circle") }
                else {
                    Button("允许通知") { Task { await requestNotifications() } }.disabled(permissionBusy).accessibilityIdentifier("proactive.permission")
                    Button("打开系统设置") { openSettings() }
                }
                Button("立即测试通知") { Task { await service?.testNotification() } }.disabled(!hasPermission).accessibilityIdentifier("proactive.test")
                Button("准备未来问候") { Task { await service?.refresh(foreground: true) } }.disabled(!enabled || !hasPermission || service?.refreshing == true)
                if service?.refreshing == true { ProgressView("正在准备问候…") }
                if let notice = service?.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("通知") } footer: { Text("测试通知和你主动要求的回复会立即送达，不受自动问候次数与安静时段限制。锁屏回复需要设备在重启后至少解锁过一次，系统也可能要求解锁。") }
            Section {
                Toggle("天气情境", isOn: Binding(get: { weather }, set: { value in
                    if value { contextService.requestWeather() } else { contextService.disableWeather() }
                })).accessibilityIdentifier("context.weather")
                Text("开启并授权定位后，将约一公里精度的位置发给 Open-Meteo 获取当前天气；只有天气摘要会发给模型，位置不会写入聊天或数据库。后台不主动获取新位置。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("日历情境", isOn: Binding(get: { calendar }, set: { value in
                    if value { Task { await contextService.enableCalendar() } } else { calendar = false }
                })).accessibilityIdentifier("context.calendar")
                Text("iOS 需要完整日历访问权限才能读取。Lumi 仅读取今明两天事件的标题和时间，并发给你配置的模型；不会新增或修改事件。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("电量与充电情境", isOn: $battery).accessibilityIdentifier("context.battery")
                Text("开启后，电量百分比和充电状态会随请求发给模型。关闭任意情境后，将取消含该情境的未来问候，并重新准备。")
                    .font(.caption).foregroundStyle(.secondary)
                if let notice = contextService.permissionNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Text("Lumi 无法读取专注模式。若希望收到问候，请在系统设置 → 专注模式 → 允许通知的 App 中加入 Lumi。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("情境感知 · 默认关闭") }
            Section {
                NavigationLink("快捷指令与自动化指南") { AutomationGuideView() }.accessibilityIdentifier("proactive.guide")
                Text("系统不保证后台刷新会执行。打开 App 可补充排程；没有服务器推送，也不会持续在后台运行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("主动问候与情境").navigationBarTitleDisplayMode(.inline)
        .task { hasPermission = await LocalNotificationDriver().authorized() }
        .onChange(of: preferences) { _, _ in Task { await service?.settingsChanged() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { hasPermission = await LocalNotificationDriver().authorized() }
        }
    }
    private func requestNotifications() async {
        permissionBusy = true; defer { permissionBusy = false }
        hasPermission = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if hasPermission { await service?.refresh(foreground: true) }
    }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}

struct AutomationGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("让问候融入日常", systemImage: "bolt.heart").font(.title2.bold())
                Text("先在 Lumi 配置 API。需要通知的动作还需允许通知；情境信息始终遵循你在 Lumi 的开关。")
                GuideStep(number: "1", title: "新建个人自动化", detail: "打开系统“快捷指令”→“自动化”→“＋”，选择到达、充电器、闹钟或特定时间等触发条件。", symbol: "plus.circle")
                GuideStep(number: "2", title: "添加 Lumi 动作", detail: "搜索 Lumi，添加“让角色说话”，选择角色和到家、充电、起床、晚安或自定义场景。自定义时填写场景描述。", symbol: "sparkles")
                GuideStep(number: "3", title: "选择立即运行", detail: "选择“立即运行”；旧版系统可关闭“运行前询问”。部分触发条件仍可能要求确认，以系统提供的选项为准。", symbol: "play.circle")
                GuideStep(number: "4", title: "试运行并检查通知", detail: "保存并手动运行一次。若没有收到通知，检查 Lumi 的通知权限和专注模式允许名单。锁屏或网络限制可能影响模型回复。", symbol: "bell.badge")
                Text("另外两个动作：“对角色说一句话”发送消息并通知回复；“给角色发送一条消息并获取回复”将文字结果交给后续动作，也可选择通知。你可在快捷指令中将结果朗读或显示。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Siri 示例：“用 Lumi 让角色说话”、“用 Lumi 对角色说句话”、“用 Lumi 获取角色回复”。首次使用可能需要选择角色和填写内容。")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.navigationTitle("自动化指南").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ProactiveSettingsView() }
        .modelContainer(for: LumiSchema.models, inMemory: true)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .tint(.lumiAccent)
}
