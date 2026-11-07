import Foundation

struct ProfileBirthday: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }
    var date: Date? {
        let calendar = Calendar(identifier: .gregorian)
        guard (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              ProfileBirthday(date) == self else { return nil }
        return date
    }
    func isValid(now: Date = .now) -> Bool {
        guard let date else { return false }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: now)
    }
}

enum ZodiacSign: String, Codable, CaseIterable, Identifiable, Sendable {
    case capricorn, aquarius, pisces, aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .capricorn: "摩羯座"
        case .aquarius: "水瓶座"
        case .pisces: "双鱼座"
        case .aries: "白羊座"
        case .taurus: "金牛座"
        case .gemini: "双子座"
        case .cancer: "巨蟹座"
        case .leo: "狮子座"
        case .virgo: "处女座"
        case .libra: "天秤座"
        case .scorpio: "天蝎座"
        case .sagittarius: "射手座"
        }
    }
    static func forBirthday(_ birthday: ProfileBirthday) -> Self {
        let day = birthday.month * 100 + birthday.day
        return switch day {
        case 120...218: .aquarius
        case 219...320: .pisces
        case 321...419: .aries
        case 420...520: .taurus
        case 521...621: .gemini
        case 622...722: .cancer
        case 723...822: .leo
        case 823...922: .virgo
        case 923...1023: .libra
        case 1024...1122: .scorpio
        case 1123...1221: .sagittarius
        default: .capricorn
        }
    }
}

struct PersonalProfile: Codable, Equatable, Sendable {
    static let storageKey = "user.personalProfile"
    static let completedKey = "user.personalProfileCompleted"
    var name = ""
    var avatarData: Data?
    var birthday: ProfileBirthday?
    var zodiacOverride: ZodiacSign?
    var displayName: String { name.isEmpty ? String(localized: "我", locale: AppLocale.current) : name }
    var zodiac: ZodiacSign? { zodiacOverride ?? birthday.map(ZodiacSign.forBirthday) }

    static func decode(_ data: Data) -> Self { (try? JSONDecoder().decode(Self.self, from: data)) ?? Self() }
    static func load(defaults: UserDefaults = AppPreferences.defaults) -> Self {
        decode(defaults.data(forKey: storageKey) ?? Data())
    }
    static func needsSetup(data: Data, completed: Bool) -> Bool {
        if completed { return false }
        guard let profile = try? JSONDecoder().decode(Self.self, from: data),
              (try? profile.validate()) != nil else { return true }
        return profile.name.isEmpty && profile.avatarData == nil && profile.birthday == nil && profile.zodiacOverride == nil
    }
    func validate() throws {
        guard name.count <= 40, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              birthday?.isValid() ?? true else { throw PersonalProfileError.fields }
        if let avatarData {
            guard !avatarData.isEmpty, avatarData.count <= 5_000_000 else { throw PersonalProfileError.image }
            try MemeArchive.validateImage(avatarData)
        }
    }
    func save(defaults: UserDefaults = AppPreferences.defaults) throws {
        try validate()
        defaults.set(try JSONEncoder().encode(self), forKey: Self.storageKey)
        defaults.set(true, forKey: Self.completedKey)
    }
}

enum PersonalProfileError: LocalizedError {
    case fields, image
    var errorDescription: String? {
        switch self {
        case .fields: String(localized: "名称最多 40 个字，生日不能晚于今天。", locale: AppLocale.current)
        case .image: String(localized: "头像无法读取，请重新选择图片。", locale: AppLocale.current)
        }
    }
}
