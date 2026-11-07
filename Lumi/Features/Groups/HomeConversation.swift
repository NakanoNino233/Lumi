import SwiftUI

struct HomeConversation: Identifiable {
    let friend: ConversationSummary?
    let group: GroupChat?
    let latest: GroupMessage?
    var unreadCount = 0
    init(friend: ConversationSummary) { self.friend = friend; group = nil; latest = nil }
    init(group: GroupChat, latest: GroupMessage?, unreadCount: Int = 0) { self.group = group; self.latest = latest; friend = nil; self.unreadCount = unreadCount }
    var id: UUID { friend?.id ?? group!.id }
    var pinnedAt: Date? { friend?.friend.pinnedAt ?? group?.pinnedAt }
    var date: Date { friend?.date ?? group!.lastMessageAt }
    func setPin(_ date: Date?) { if let friend { friend.friend.pinnedAt = date } else { group?.pinnedAt = date } }
    static func precedes(_ left: Self, _ right: Self) -> Bool {
        if let a = left.pinnedAt, let b = right.pinnedAt, a != b { return a > b }
        if (left.pinnedAt != nil) != (right.pinnedAt != nil) { return left.pinnedAt != nil }
        if left.date != right.date { return left.date > right.date }
        return left.id.uuidString < right.id.uuidString
    }
}
struct HomeConversationRow: View {
    let entry: HomeConversation
    var onOpen: (LumiCharacter) -> Void
    var onOpenGroup: (GroupChat) -> Void
    var body: some View {
        Button {
            if let friend = entry.friend { onOpen(friend.friend) }
            else if let group = entry.group { onOpenGroup(group) }
        } label: {
            HStack {
                if let friend = entry.friend { ConversationSummaryRow(row: friend) }
                else if let group = entry.group { GroupConversationRow(group: group, latest: entry.latest, unreadCount: entry.unreadCount) }
            }
        }.buttonStyle(.plain).accessibilityIdentifier(entry.friend.map { "conversation.\($0.friend.name)" } ?? "group.conversation.\(entry.group?.name ?? "")")
    }
}

struct UnreadBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.bold()).foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 5 : 0).frame(minWidth: 20, minHeight: 20)
                .background(.red, in: Capsule())
                .accessibilityLabel("\(count) 条未读消息")
        }
    }
}
