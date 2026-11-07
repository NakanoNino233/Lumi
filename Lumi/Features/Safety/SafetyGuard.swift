import Foundation

enum SafetyGuard {
    static var support: String {
        String(localized: "听起来你现在很难受，我很关心你的安全。请先联系身边可信的人陪着你；如果有立即的危险，请联系当地紧急服务或前往急诊。你不需要独自承受。", locale: AppLocale.current)
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
    static func isCrisis(_ text: String) -> Bool {
        let value = normalized(text)
        return ["我想自杀", "我要自杀", "不想活了", "想结束生命", "想伤害自己", "我想死", "我准备自杀", "我已经吞了很多药", "我已经吃了很多药", "killmyself", "wanttodie", "endmylife", "hurtmyself", "suicidal", "goingtokillmyself"].contains { value.contains($0) }
    }
    static func needsAssessment(_ text: String) -> Bool {
        let value = normalized(text)
        return ["永远睡着", "再也醒不过来", "撑不下去", "告别这个世界", "最后一封信", "遗书", "活着没意义", "不会有明天", "消失就好了", "disappearforever", "wontbeheretomorrow", "cantgoon", "finalgoodbye"].contains { value.contains($0) }
    }
    static func assessmentTurns(_ text: String) -> [ChatTurn] {
        [ChatTurn(role: "system", content: PromptBuilder.resource("SafetyAssessment")),
         ChatTurn(role: "user", content: PromptBuilder.dataBlock(["userText": String(text.suffix(6000))]))]
    }
    static func assess(_ text: String, client: any ChatClient, endpoint: ProviderEndpoint, key: String) async throws -> Bool {
        if isCrisis(text) { return true }
        guard needsAssessment(text) else { return false }
        guard !key.isEmpty else { return true }
        do {
            let raw = try await client.complete(endpoint: endpoint.function(.safety), key: key, messages: assessmentTurns(text), limit: 48)
            try Task.checkCancellation()
            struct Verdict: Decodable { let crisis: Bool }
            guard raw.utf8.count <= 500, let verdict = try? JSONDecoder().decode(Verdict.self, from: Data(raw.utf8)) else { return true }
            return verdict.crisis
        } catch is CancellationError { throw CancellationError() }
        catch { return true } // Uncertain concerning messages receive the local support response.
    }
}
