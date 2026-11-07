import SwiftUI
import PhotosUI
import UIKit

struct PersonalAvatar: View {
    var size: CGFloat = 34
    @AppStorage(PersonalProfile.storageKey, store: AppPreferences.defaults) private var profileData = Data()
    @State private var avatar: UIImage?
    var body: some View {
        ProfileAvatarImage(image: avatar, size: size)
            .task(id: profileData) { avatar = PersonalProfile.decode(profileData).avatarData.flatMap(UIImage.init(data:)) }
    }
}

private struct ProfileAvatarImage: View {
    let image: UIImage?
    let size: CGFloat
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(theme.accent) }
        }
        .frame(width: size, height: size)
        .background(theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
        .accessibilityHidden(true)
    }
}

struct PersonalProfileEditor: View {
    let isOnboarding: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonalProfile
    @State private var photo: PhotosPickerItem?
    @State private var avatar: UIImage?
    @State private var loadingPhoto = false
    @State private var error: String?
    @State private var birthdayExpanded = false
    @FocusState private var nameFocused: Bool
    init(profile: PersonalProfile, isOnboarding: Bool = false) {
        _draft = State(initialValue: profile)
        self.isOnboarding = isOnboarding
    }
    private var cleanName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var saveTitle: LocalizedStringResource { isOnboarding ? "保存并继续" : "保存" }
    var body: some View {
        Form {
            if isOnboarding { ProfileSetupIntroduction() }
            Section {
                HStack(spacing: 16) {
                    ProfileAvatarImage(image: avatar, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $photo, matching: .images) { Label("更换头像", systemImage: "photo") }
                            .accessibilityIdentifier("profile.avatar.choose")
                        if draft.avatarData != nil {
                            Button("移除头像", role: .destructive) { photo = nil; draft.avatarData = nil; avatar = nil }
                                .accessibilityIdentifier("profile.avatar.remove")
                        }
                        if loadingPhoto { ProgressView() }
                    }
                }.padding(.vertical, 8)
            }
            Section {
                LabeledContent("名称") {
                    TextField("填写你的名称", text: $draft.name)
                        .multilineTextAlignment(.trailing).textContentType(.nickname).submitLabel(.done)
                        .focused($nameFocused).onSubmit { nameFocused = false }
                        .accessibilityIdentifier("profile.name")
                }
            } footer: { Text("最多 40 个字").foregroundStyle(cleanName.count > 40 ? Color.red : Color.secondary) }
            ProfileBirthdaySection(birthday: $draft.birthday, expanded: $birthdayExpanded)
            Section {
                Picker("星座", selection: $draft.zodiacOverride) {
                    Text("根据生日自动计算").tag(Optional<ZodiacSign>.none)
                    ForEach(ZodiacSign.allCases) { sign in Text(sign.title).tag(Optional(sign)) }
                }.pickerStyle(.menu).accessibilityIdentifier("profile.zodiac")
                if draft.zodiacOverride == nil, let zodiac = draft.zodiac {
                    LabeledContent("当前星座") { Text(zodiac.title) }
                }
            } footer: { Text("可以根据生日自动计算，也可以手动选择。") }
        }
        .navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("profile.cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveTitle, action: save)
                    .disabled((isOnboarding && cleanName.isEmpty) || cleanName.count > 40 || loadingPhoto || photo != nil)
                    .accessibilityIdentifier("profile.save")
            }
        }
        .task { avatar = draft.avatarData.flatMap(UIImage.init(data:)) }
        .task(id: photo) {
            guard let selection = photo else { return }
            loadingPhoto = true
            defer { loadingPhoto = false; if photo == selection { photo = nil } }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw PersonalProfileError.image }
                try Task.checkCancellation()
                let normalized = try CharacterImage.normalized(data)
                guard let image = UIImage(data: normalized) else { throw PersonalProfileError.image }
                draft.avatarData = normalized; avatar = image
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
        .alert("无法保存个人资料", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save() {
        do {
            draft.name = cleanName
            try draft.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ProfileSetupIntroduction: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("先认识一下你").font(.title2.weight(.semibold))
                Text("填一个喜欢的名称。头像、生日和星座可以留空，以后随时在“我的”里修改。")
                    .foregroundStyle(.secondary)
                Text("聊天时，好友会参考你填写的名称、生日和星座来了解你。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
        }.accessibilityIdentifier("profile.setup.introduction")
    }
}

private struct ProfileBirthdaySection: View {
    @Binding var birthday: ProfileBirthday?
    @Binding var expanded: Bool
    private var initialDate: Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12))! }
    private var selectedDate: Binding<Date> {
        Binding(get: { birthday?.date ?? initialDate }, set: { birthday = ProfileBirthday($0) })
    }
    var body: some View {
        Section {
            Button {
                if birthday == nil { birthday = ProfileBirthday(initialDate) }
                expanded.toggle()
            } label: {
                HStack {
                    Text("生日").foregroundStyle(.primary)
                    Spacer()
                    if let date = birthday?.date { Text(date, format: .dateTime.year().month().day()) }
                    else { Text("未设置").foregroundStyle(.secondary) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
            }.accessibilityIdentifier("profile.birthday")
            if expanded {
                DatePicker("生日", selection: selectedDate, in: initialLowerBound...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).environment(\.calendar, Calendar(identifier: .gregorian))
                    .accessibilityIdentifier("profile.birthday.picker")
            }
            if birthday != nil {
                Button("清除生日", role: .destructive) { birthday = nil; expanded = false }
                    .accessibilityIdentifier("profile.birthday.clear")
            }
        }
    }
    private var initialLowerBound: Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 1900, month: 1, day: 1))! }
}
