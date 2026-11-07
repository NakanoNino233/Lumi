import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var providers: [ProviderConfig]
    @AppStorage("onboardingStep", store: AppPreferences.defaults) private var onboardingStep = 0
    @AppStorage(PersonalProfile.storageKey, store: AppPreferences.defaults) private var profileData = Data()
    @AppStorage(PersonalProfile.completedKey, store: AppPreferences.defaults) private var profileCompleted = false
    @State private var bootstrapError = false
    @State private var restoredID = UUID()
    var body: some View {
        Group {
            if onboardingStep <= 1 {
                NavigationStack { PrivacyConsentView { onboardingStep = 2 } }
            } else if PersonalProfile.needsSetup(data: profileData, completed: profileCompleted) {
                NavigationStack { PersonalProfileEditor(profile: PersonalProfile.decode(profileData), isOnboarding: true) }
            } else if let provider = providers.first {
                if onboardingStep == 2 {
                    NavigationStack { ProviderSettingsView(config: provider, isOnboarding: true) { onboardingStep = 3 } }
                } else {
                    CharacterHomeView(provider: provider)
                }
            } else if bootstrapError {
                ContentUnavailableView {
                    Label("本地保存失败", systemImage: "externaldrive.badge.exclamationmark")
                } actions: { Button("重试") { prepareProvider() } }
            } else { ProgressView() }
        }
        .id(restoredID)
        .onReceive(NotificationCenter.default.publisher(for: .lumiDidRestore)) { _ in restoredID = UUID() }
        .task { prepareProvider() }
        .modifier(LumiLaunchPresentation())
        .modifier(WellbeingReminder())
        .modifier(TokenLimitReminder())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ProactiveService.shared?.launchRefresh(foreground: true); Task { await SigningReminder.refresh() } }
            else if phase == .background { ProactiveService.shared?.launchRefresh(foreground: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await ProactiveService.shared?.settingsChanged() }
        }
    }
    private func prepareProvider() {
        do {
            // Fetch directly to avoid duplicate insertion before @Query refreshes.
            let existing = try context.fetch(FetchDescriptor<ProviderConfig>())
            if existing.isEmpty {
                context.insert(ProviderConfig()); try context.save()
            } else { for config in existing { try ProviderDefaults.upgrade(config, context: context) } }
            bootstrapError = false
        } catch { bootstrapError = true }
    }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 12) {
            LumiBrandIcon(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Lumi").font(.system(.largeTitle, design: .rounded).weight(.medium))
                Text("陪伴，有一点光").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LumiBrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image("LumiLogo").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("你的对话，由你掌握", systemImage: "lock.shield").font(.title2.bold())
                PrivacyItem(title: "本地保存", detail: "聊天记录、角色与配置保存在本机，Lumi 不设后台服务器，不接入统计或广告 SDK。")
                PrivacyItem(title: "由你选择模型", detail: "发送消息或测试连接时，对话内容会发送给你配置的模型服务商，其数据处理规则由该服务商决定。")
                PrivacyItem(title: "密钥留在钥匙串", detail: "API Key 仅保存在设备钥匙串，不写入聊天数据库、偏好设置、日志或导出文件。")
                PrivacyItem(title: "附件与好友生成", detail: "发送消息时，图片或文件的文字节选会发送给你配置的模型。聊天附件随消息保存在本机；用于生成好友的原始聊天记录不保存，只保存生成的人设。")
                PrivacyItem(title: "表情与学图", detail: "图库图片留在本机；聊天选图只把描述提供给模型。只有确认 AI 学图后，预览图才会发送给你配置的视觉模型。GIF 使用抽帧拼图。")
                PrivacyItem(title: "技能与工具", detail: "技能只包含参考文字，不运行代码。读取日历、获取附近天气、保存记忆、设置提醒或播放声音等工具操作会先在聊天里请求授权；结果会提供给当前模型。始终允许可在工具授权中撤销。")
                PrivacyItem(title: "语音与分享", detail: "语音消息保存在本机并可回放；支持时由系统本机识别，转写文字交给你配置的模型，录音不会发送给额外的识别服务。备份和分享只在你操作时生成，包含私人资料，请妥善保存。锁屏最近回复默认隐藏，只有主动开启才会显示。")
                PrivacyItem(title: "记忆由你掌握", detail: "开启自动记忆后，每 8 轮对话或离开聊天时，会将近期对话发送给你配置的服务商整理记忆；每日小结也由该模型生成。你可以关闭自动整理，并随时编辑或删除本地记忆。")
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.navigationTitle("隐私说明").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyItem: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrivacyConsentView: View {
    var onContinue: () -> Void
    var body: some View {
        PrivacyView().safeAreaInset(edge: .bottom) {
            Button { onContinue() } label: { Text("已阅读，配置我的 API") }
                .lumiProminentButton().controlSize(.large).padding().frame(maxWidth: .infinity).background(.bar).accessibilityIdentifier("onboarding.privacy")
        }
    }
}

#Preview { LumiSplashView() }
