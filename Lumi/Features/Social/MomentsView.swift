import SwiftUI
import SwiftData
import PhotosUI

struct MomentsView: View {
    var friend: LumiCharacter? = nil
    @Query(sort: \MomentPost.createdAt, order: .reverse) private var posts: [MomentPost]
    @Query(sort: \LumiCharacter.createdAt) private var friends: [LumiCharacter]
    @State private var composing = false
    @State private var options = false
    init(friend: LumiCharacter? = nil) {
        self.friend = friend
        if let id = friend?.id {
            _posts = Query(filter: #Predicate<MomentPost> { $0.authorID == id }, sort: \MomentPost.createdAt, order: .reverse)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                MomentsCover(friend: friend)
                if friend == nil { MomentFriendsStrip(friends: friends) }
                if posts.isEmpty {
                    ContentUnavailableView(friend == nil ? "把今天留在这里" : "还没有动态", systemImage: "camera.aperture", description: Text(friend == nil ? "发一张照片，或写下一件值得记住的小事。" : "好友发布的生活片段会出现在这里。"))
                        .padding(.vertical, 32)
                }
                ForEach(posts) { post in
                    MomentRow(post: post, friend: friends.first { $0.id == post.authorID }, showsProfileLink: friend == nil)
                }
                Text("动态保存在这台设备").font(.caption2).foregroundStyle(.secondary).padding(24)
            }
        }
        .navigationTitle(friend.map { "\($0.name)的朋友圈" } ?? "朋友圈").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if friend == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("朋友圈设置", systemImage: "slider.horizontal.3") { options = true }.accessibilityIdentifier("moments.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("发布动态", systemImage: "camera") { composing = true }.accessibilityIdentifier("moments.compose")
                }
            }
        }
        .sheet(isPresented: $composing) { NavigationStack { MomentComposer() } }
        .sheet(isPresented: $options) { NavigationStack { MomentsOptionsView() } }
    }
}

private struct MomentFriendsStrip: View {
    let friends: [LumiCharacter]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(friends) { friend in
                    NavigationLink {
                        MomentsView(friend: friend)
                    } label: {
                        VStack(spacing: 6) {
                            CharacterAvatar(data: friend.avatarData, size: 48)
                            Text(friend.name).font(.caption).lineLimit(1)
                        }.frame(width: 64)
                    }.buttonStyle(.plain).accessibilityIdentifier("moments.friend.\(friend.name)")
                }
            }.padding(16)
        }.scrollIndicators(.hidden)
    }
}

struct MomentsCover: View {
    var friend: LumiCharacter? = nil
    @Environment(\.lumiTheme) private var theme
    @AppStorage("moments.cover", store: AppPreferences.defaults) private var cover = Data()
    @AppStorage(MomentsPreferences.tagsKey, store: AppPreferences.defaults) private var storedTags = ""
    @State private var editingTags = false
    @State private var selection: PhotosPickerItem?
    @State private var picking = false
    @State private var image: UIImage?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        let tags = MomentsTags.visible(storedTags)
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geometry in
                if let image, friend == nil {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .accessibilityLabel("自定义朋友圈背景").accessibilityIdentifier("moments.cover.custom")
                } else if let friend, CharacterCard.normalized(friend.name) == CharacterCard.normalized("大肥鱼") {
                    Image("DaughterMomentsCover").resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .accessibilityLabel("好友朋友圈背景").accessibilityIdentifier("moments.cover.daughter")
                } else {
                    LinearGradient(colors: [theme.accent.opacity(0.12), theme.accent.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "sparkle").font(.system(size: 110)).foregroundStyle(.white.opacity(0.4)).offset(x: 30, y: 25)
                }
            }
            VStack(alignment: .trailing, spacing: 10) {
                if friend == nil {
                    Button { picking = true } label: {
                        Label(loading ? "正在更换…" : "更换背景", systemImage: "photo")
                            .font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                    }.disabled(loading).accessibilityIdentifier("moments.cover.change")
                    Spacer(minLength: 0)
                }
                if friend == nil {
                    Button { editingTags = true } label: {
                        if tags.isEmpty {
                            Label("添加个性化标签", systemImage: "tag")
                                .font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                        } else { MomentsTagList(tags: tags) }
                    }.buttonStyle(.plain).accessibilityLabel("编辑个性化标签")
                        .accessibilityValue(tags.joined(separator: "，"))
                        .accessibilityIdentifier("moments.tags.edit")
                } else {
                    Text("生活里的小小片段")
                        .font(.system(.title3, design: .rounded).weight(.medium)).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Text(friend?.name ?? "我").font(.headline).padding(6).background(.regularMaterial, in: Capsule())
                    if let friend { CharacterAvatar(data: friend.avatarData, size: 64) }
                    else { PersonalAvatar(size: 64) }
                }
            }.padding(20)
        }.frame(minHeight: friend == nil && tags.count > 1 ? 280 : 240).clipped()
        .photosPicker(isPresented: $picking, selection: $selection, matching: .images)
        .sheet(isPresented: $editingTags) { NavigationStack { MomentsTagsEditor(tags: storedTags) } }
        .task(id: cover) { image = UIImage(data: cover) }
        .task(id: selection) {
            guard let selection else { return }
            loading = true; defer { loading = false; self.selection = nil }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw AttachmentError.unreadable }
                let normalized = try CharacterImage.normalized(data)
                try Task.checkCancellation(); cover = normalized
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
        .alert("背景更换失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
}

private struct MomentsOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("moments.automatic", store: AppPreferences.defaults) private var automatic = true
    @AppStorage("moments.cover", store: AppPreferences.defaults) private var cover = Data()
    @AppStorage(MomentsPreferences.tagsKey, store: AppPreferences.defaults) private var storedTags = ""
    @Query private var providers: [ProviderConfig]
    var body: some View {
        Form {
            Section("个性化") {
                NavigationLink("个性化标签") { MomentsTagsEditor(tags: storedTags) }
                    .accessibilityIdentifier("moments.tags.settings")
            }
            Section {
                Toggle("好友自动发动态与互动", isOn: $automatic).accessibilityIdentifier("moments.automatic")
                Text("App 使用期间，好友会按各自节奏分享生活，每人约 6～10 小时最多一条，也会选择性点赞、评论。新好友同样适用。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("使用你配置的模型，会消耗额度。好友只能看到朋友圈公开内容。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("检查好友动态") { Task { await MomentsService.shared?.refresh() } }
                    .disabled(!automatic || MomentsService.shared?.refreshing == true)
                if MomentsService.shared?.refreshing == true { ProgressView("好友正在逛朋友圈…") }
                if let notice = MomentsService.shared?.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if let provider = providers.first { NavigationLink("模型连接设置") { ProviderSettingsView(config: provider) } }
            }
            Section("封面") {
                Text("点击朋友圈顶部的“更换背景”，即可从相册选择照片。")
                Button("恢复默认背景", role: .destructive) { cover = Data() }.disabled(cover.isEmpty)
            }
        }.navigationTitle("朋友圈设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onChange(of: automatic) { _, enabled in
            if enabled { Task { await MomentsService.shared?.refresh() } }
            else { MomentsService.shared?.pause() }
        }
    }
}

private struct MomentsTagList: View {
    let tags: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(tags, id: \.self) { MomentsTagChip(text: $0) } }
            VStack(alignment: .trailing, spacing: 6) { ForEach(tags, id: \.self) { MomentsTagChip(text: $0) } }
        }
    }
}

private struct MomentsTagChip: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).fixedSize().padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

private struct MomentsTagsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MomentsPreferences.tagsKey, store: AppPreferences.defaults) private var storedTags = ""
    @State private var draft: String
    init(tags: String) { _draft = State(initialValue: tags) }
    var body: some View {
        Form {
            Section {
                TextField("例如：爱拍照，慢热，喜欢猫", text: $draft, axis: .vertical)
                    .lineLimit(2...4).accessibilityIdentifier("moments.tags.input")
                if !MomentsTags.isValid(draft) {
                    Text("标签过多或过长，请修改后保存。").font(.footnote).foregroundStyle(.red)
                }
            } footer: { Text("最多 3 个标签，每个不超过 12 个字，用逗号分隔。标签会显示在你的朋友圈封面上。") }
            let tags = MomentsTags.visible(draft)
            if !tags.isEmpty {
                Section("预览") {
                    MomentsTagList(tags: tags).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Section {
                Button("清空标签", role: .destructive) { draft = "" }
                    .disabled(draft.isEmpty).accessibilityIdentifier("moments.tags.clear")
            }
        }
        .navigationTitle("个性化标签").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("moments.tags.cancel") }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { storedTags = MomentsTags.parse(draft).joined(separator: "，"); dismiss() }
                    .disabled(!MomentsTags.isValid(draft)).accessibilityIdentifier("moments.tags.save")
            }
        }
    }
}

struct MomentRow: View {
    let post: MomentPost
    var friend: LumiCharacter? = nil
    var showsProfileLink = true
    @Environment(\.modelContext) private var context
    @State private var comment = ""
    @State private var commenting = false
    @State private var replyTo: MomentComment?
    @State private var deleting = false
    @State private var error: String?
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let friend {
                CharacterAvatar(data: friend.avatarData, size: 42)
            } else if post.authorID == nil {
                PersonalAvatar(size: 42)
            } else {
                CharacterAvatar(data: nil, size: 42)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let friend, showsProfileLink {
                    NavigationLink(friend.name) { MomentsView(friend: friend) }.font(.headline).foregroundStyle(theme.accent)
                } else { Text(friend?.name ?? post.displayName).font(.headline).foregroundStyle(theme.accent) }
                if !post.content.isEmpty { Text(post.content).textSelection(.enabled) }
                MomentImages(items: post.images)
                HStack {
                    Text(post.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { mutate { post.liked.toggle() } } label: { Image(systemName: post.liked ? "heart.fill" : "heart") }
                        .accessibilityLabel(post.liked ? "取消点赞" : "点赞").accessibilityIdentifier("moments.like.\(post.id)")
                    Button { replyTo = nil; commenting.toggle() } label: { Image(systemName: "bubble.right") }.accessibilityLabel("评论")
                    Menu { Button("删除动态", systemImage: "trash", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("动态操作")
                }.foregroundStyle(theme.accent)
                if !post.likeNames.isEmpty {
                    Label(post.likeNames.joined(separator: "、"), systemImage: "heart.fill").font(.caption).foregroundStyle(theme.accent)
                }
                ForEach(post.comments) { entry in
                    Button {
                        replyTo = entry; commenting = true
                    } label: {
                        Text("\(entry.displayName)\(entry.replyToName.map { " 回复 " + $0 } ?? "")：\(entry.text)")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel("\(entry.displayName)：\(entry.text)，点击回复")
                }
                if commenting {
                    if let replyTo { HStack { Text("回复 \(replyTo.displayName)").font(.caption); Button("取消回复") { self.replyTo = nil } } }
                    HStack {
                        TextField("写评论…", text: $comment).textFieldStyle(.roundedBorder).accessibilityIdentifier("moments.comment.text")
                        Button("发送") { sendComment() }
                            .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || comment.count > 500 || post.comments.count >= 100)
                            .accessibilityIdentifier("moments.comment.send")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 74) }
        .confirmationDialog("删除这条动态及全部点赞和评论？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除动态", role: .destructive) { mutate { context.delete(post) } }
        }
    }
    private func sendComment() {
        let clean = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500, post.comments.count < 100 else { return }
        if mutate({ post.comments.append(MomentComment(text: clean, createdAt: .now, replyToID: replyTo?.id, replyToName: replyTo?.displayName)) }) {
            comment = ""; commenting = false; replyTo = nil
            MomentsService.shared?.requestRefresh(for: post.id)
        }
    }
    @discardableResult private func mutate(_ change: () -> Void) -> Bool {
        change()
        do { try context.save(); return true } catch { context.rollback(); self.error = LLMError.storage.localizedDescription; return false }
    }
}

struct MomentImages: View {
    let items: [ChatAttachment]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 160))], alignment: .leading, spacing: 6) {
            ForEach(items) { item in AttachmentBubble(item: item) }
        }
    }
}

struct MomentComposer: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selection: [PhotosPickerItem] = []
    @State private var images: [ChatAttachment] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("这一刻，想分享什么？", text: $text, axis: .vertical).lineLimit(5...12).accessibilityIdentifier("moments.text")
                PhotosPicker(selection: $selection, maxSelectionCount: 4, matching: .images) { Label("添加照片", systemImage: "photo.on.rectangle") }
                if loading { ProgressView() }
                ForEach(images) { item in HStack { AttachmentThumbnail(item: item); Spacer(); Button("移除") { images.removeAll { $0.id == item.id } } } }
            } footer: { Text("最多 2000 字、4 张图片。动态仅保存在本机。") }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle("发布动态").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("发布") {
                let post = MomentPost(content: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images)
                context.insert(post)
                do { try context.save(); MomentsService.shared?.requestRefresh(for: post.id); dismiss() } catch { context.delete(post); self.error = LLMError.storage.localizedDescription }
            }.disabled(loading || text.count > 2000 || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty)).accessibilityIdentifier("moments.publish") }
        }
        .task(id: selection) {
            guard !selection.isEmpty else { return }; loading = true; defer { loading = false }
            do {
                var result: [ChatAttachment] = []
                for item in selection { guard let data = try await item.loadTransferable(type: Data.self) else { throw AttachmentError.unreadable }; result.append(try ChatAttachment.image(data)); try Task.checkCancellation() }
                try ChatAttachment.validate(result, supportsVision: true); images = result
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
}
