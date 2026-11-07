import SwiftUI
import SwiftData
import Observation

@MainActor @Observable final class ProviderEditor {
    var name = "DeepSeek"
    var baseURL = "https://api.deepseek.com"
    var model = ProviderDefaults.model
    var key = ""
    var supportsTools = true
    var supportsVision = true
    var notice: String?
    var isTesting = false
    var testSucceeded = false
    private var testTask: Task<Void, Never>?
    private var configID: UUID?
    private let keychain = KeychainStore()
    func load(_ config: ProviderConfig) {
        guard configID != config.id else { return }
        configID = config.id
        name = config.name; baseURL = config.baseURL; model = config.modelName
        supportsTools = config.supportsTools; supportsVision = config.supportsVision
        do { key = try keychain.read(for: config.id) ?? "" }
        catch { notice = LLMError.keychain.localizedDescription }
    }
    var template: String { ["DeepSeek", "ChatGPT", "Claude"].contains(name) ? name : "Custom" }
    func preset(_ value: String) {
        name = value; key = ""; notice = nil
        supportsTools = true; supportsVision = true
        switch value {
        case "DeepSeek": baseURL = "https://api.deepseek.com"; model = ProviderDefaults.model
        case "ChatGPT": baseURL = "https://api.openai.com/v1"; model = "gpt-6-luna"
        case "Claude": baseURL = "https://api.anthropic.com/v1"; model = "claude-sonnet-5-5"
        default: baseURL = ""; model = ""
        }
    }
    var endpoint: ProviderEndpoint { ProviderEndpoint(baseURL: baseURL, model: model) }
    func save(config: ProviderConfig, context: ModelContext) -> Bool {
        do {
            _ = try endpoint.completionURL()
            let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanKey.isEmpty else { throw LLMError.missingKey }
            // Restore both metadata and key if the local database transaction fails.
            let old = (config.name, config.baseURL, config.modelName, config.supportsTools, config.supportsVision)
            let oldKey = try keychain.read(for: config.id)
            try keychain.save(cleanKey, for: config.id)
            config.name = name; config.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            config.modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
            config.supportsTools = supportsTools; config.supportsVision = supportsVision
            do { try context.save() }
            catch {
                config.name = old.0; config.baseURL = old.1; config.modelName = old.2
                config.supportsTools = old.3; config.supportsVision = old.4
                try? keychain.save(oldKey ?? "", for: config.id)
                throw LLMError.storage
            }
            notice = String(localized: "配置已保存，密钥仅存于钥匙串。", locale: AppLocale.current)
            return true
        } catch { notice = LLMError.sanitized(error).localizedDescription; return false }
    }
    func test() {
        guard !isTesting else { return }
        let endpoint = endpoint; let secret = key
        notice = nil; testSucceeded = false; isTesting = true
        testTask = Task {
            defer { isTesting = false; testTask = nil }
            do {
                let start = ContinuousClock.now
                _ = try await LLMClient().complete(endpoint: endpoint.function(.connection), key: secret, messages: [ChatTurn(role: "user", content: "Reply OK")])
                try Task.checkCancellation()
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                notice = String(localized: "连接成功，用时 \(seconds.formatted(.number.precision(.fractionLength(2)))) 秒。", locale: AppLocale.current)
                testSucceeded = true
            } catch is CancellationError { }
            catch { if !Task.isCancelled { notice = LLMError.sanitized(error).localizedDescription } }
        }
    }
    func cancelTest() { testTask?.cancel(); testTask = nil; isTesting = false }
    func forgetKey(config: ProviderConfig) {
        do { try keychain.delete(for: config.id); key = ""; notice = String(localized: "已从钥匙串移除密钥。", locale: AppLocale.current) }
        catch { notice = LLMError.keychain.localizedDescription }
    }
}

struct ProviderSettingsView: View {
    let config: ProviderConfig
    var isOnboarding = false
    var onComplete: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editor = ProviderEditor()
    @State private var showKey = false
    @State private var showDeleteConfirmation = false
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        @Bindable var editor = editor
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "key.horizontal").font(.title).foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接你的模型").font(.headline)
                        Text("使用自己的 API，开启与角色的对话。也可以稍后设置，先浏览 App。").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Picker("服务商模板", selection: Binding(get: { editor.template }, set: { editor.preset($0) })) {
                    Text("DeepSeek").tag("DeepSeek")
                    Text("ChatGPT").tag("ChatGPT")
                    Text("Claude").tag("Claude")
                    Text("自定义").tag("Custom")
                }.accessibilityIdentifier("provider.template")
                TextField("Base URL", text: $editor.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("provider.baseURL")
                HStack {
                    if showKey {
                        TextField("API Key", text: $editor.key).accessibilityIdentifier("provider.key")
                    } else {
                        SecureField("API Key", text: $editor.key).accessibilityIdentifier("provider.key")
                    }
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .accessibilityLabel(showKey ? Text("隐藏密钥") : Text("显示密钥"))
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                TextField("模型名称", text: $editor.model).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("provider.model")
                Text("选择模板后会自动填写地址和模型；使用对应服务商的 API Key，也可以自行修改模型名称。").font(.caption).foregroundStyle(.secondary)
            }
            Section("模型能力") {
                Toggle("支持工具调用", isOn: $editor.supportsTools).accessibilityIdentifier("provider.tools")
                Toggle("支持视觉", isOn: $editor.supportsVision).accessibilityIdentifier("provider.vision")
                Text("模板默认开启工具调用和视觉。更换模型时，请按模型实际支持的能力调整。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button { editor.test() } label: {
                    HStack { Text("测试连接"); Spacer(); if editor.isTesting { ProgressView() } else { Image(systemName: "bolt.horizontal") } }
                }.disabled(editor.isTesting).accessibilityIdentifier("provider.test")
                Text("测试会向当前地址发送一条极短请求，可能产生少量服务商费用。").font(.caption).foregroundStyle(.secondary)
                if let notice = editor.notice { Text(notice).font(.callout).accessibilityIdentifier("provider.notice") }
                Button(isOnboarding ? LocalizedStringKey("保存并开始聊天") : LocalizedStringKey("保存配置")) {
                    if editor.save(config: config, context: context) {
                        ProactiveService.shared?.launchRefresh(foreground: true)
                        onComplete(); if !isOnboarding { dismiss() }
                    }
                }.fontWeight(.semibold).disabled(editor.isTesting).accessibilityIdentifier("provider.save")
            }
            Section {
                NavigationLink("如何申请 DeepSeek Key") { DeepSeekGuideView() }
                NavigationLink("隐私说明") { PrivacyView() }
                if !isOnboarding { Button("移除已保存的密钥", role: .destructive) { showDeleteConfirmation = true } }
            }
        }
        .navigationTitle("API 配置").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOnboarding {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("稍后设置") { editor.cancelTest(); onComplete() }.accessibilityIdentifier("provider.skip")
                }
            }
        }
        .task { editor.load(config) }
        .onDisappear { editor.cancelTest() }
        .confirmationDialog("移除密钥后需要重新配置才能聊天。", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("移除密钥", role: .destructive) { editor.forgetKey(config: config) }
        }
    }
}

struct DeepSeekGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("准备你的 API Key", systemImage: "key.fill").font(.title2.bold())
                Text("在 DeepSeek 开放平台创建 API Key 后，回到 Lumi 填写。")
                GuideStep(number: "1", title: "登录服务商平台", detail: "在浏览器中打开 DeepSeek 开放平台，使用你自己的账户登录。", symbol: "globe")
                GuideStep(number: "2", title: "创建 API Key", detail: "在 API Keys 页面创建密钥，并复制保存。请勿把密钥发给他人。", symbol: "key.horizontal")
                GuideStep(number: "3", title: "返回 Lumi 配置", detail: "选择 DeepSeek 模板，粘贴密钥，确认模型名称后测试连接。", symbol: "checkmark.shield")
                Text("默认模型为 DeepSeek V4.1 Flash。Lumi 不代购或收取模型费用。").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle("申请密钥")
    }
}

struct GuideStep: View {
    let number: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(number).font(.title3.monospaced().bold()); Text(title).font(.headline) }
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(theme.accent).frame(maxWidth: .infinity).frame(height: 90).background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}
