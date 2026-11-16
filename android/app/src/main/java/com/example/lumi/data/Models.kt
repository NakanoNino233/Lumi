package com.example.lumi.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID

fun newId(): String = UUID.randomUUID().toString()
fun now(): Long = System.currentTimeMillis()
fun today(): String = LocalDate.now().toString()
fun JSONObject.text(key: String, default: String = ""): String = if (isNull(key)) default else optString(key, default)
fun JSONObject.objects(key: String): List<JSONObject> = optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getJSONObject(it) } } ?: emptyList()
fun JSONObject.strings(key: String): List<String> = optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
fun json(vararg pairs: Pair<String, Any?>): JSONObject = JSONObject().apply { pairs.forEach { (k, v) -> put(k, v ?: JSONObject.NULL) } }
fun arr(items: List<Any>): JSONArray = JSONArray(items)

data class Friend(
    val id: String = newId(), val name: String = "", val persona: String = "",
    val style: String = "", val background: String = "", val taboos: String = "",
    val greeting: String = "", val avatar: String = "", val emoji: String = "🌱",
    val affection: Int = 0, val pinned: Boolean = false, val created: Long = now(),
    val affectionDay: String = "", val dailyGain: Int = 0, val momentsCover: String = ""
) {
    val stage: String get() = when { affection >= 80 -> "亲密"; affection >= 55 -> "亲近"; affection >= 25 -> "熟悉"; else -> "初识" }
    fun card(): JSONObject = json("schemaVersion" to 1, "name" to name, "personaPrompt" to persona,
        "speechStyle" to style, "backgroundStory" to background, "taboos" to taboos,
        "firstGreeting" to greeting, "avatar" to avatar.takeIf { it.isNotEmpty() })
    fun toJson(): JSONObject = card().put("id", id).put("emoji", emoji).put("affection", affection)
        .put("pinned", pinned).put("created", created).put("affectionDay", affectionDay).put("dailyGain", dailyGain).put("momentsCover", momentsCover)
    companion object {
        fun from(o: JSONObject): Friend = Friend(o.text("id", newId()), o.text("name"), o.text("personaPrompt"),
            o.text("speechStyle"), o.text("backgroundStory"), o.text("taboos"), o.text("firstGreeting"),
            o.text("avatar", o.text("avatarData")), o.text("emoji", "🌱"), o.optInt("affection").coerceIn(0, 100),
            o.optBoolean("pinned"), o.optLong("created", now()), o.text("affectionDay"), o.optInt("dailyGain").coerceIn(0, 6), o.text("momentsCover"))
    }
}
data class Chat(val id: String = newId(), val members: List<String>, val title: String, val created: Long = now()) {
    val isGroup: Boolean get() = members.size > 1
    fun toJson() = json("id" to id, "members" to arr(members), "title" to title, "created" to created)
    companion object { fun from(o: JSONObject) = Chat(o.getString("id"), o.strings("members"), o.text("title"), o.optLong("created", now())) }
}
data class Message(
    val id: String = newId(), val chatId: String, val role: String, val content: String,
    val senderId: String = "", val image: String = "", val created: Long = now(),
    val status: String = "complete", val error: String = ""
) {
    fun toJson() = json("id" to id, "chatId" to chatId, "role" to role, "content" to content,
        "senderId" to senderId, "image" to image, "created" to created, "status" to status, "error" to error)
    companion object { fun from(o: JSONObject) = Message(o.getString("id"), o.getString("chatId"), o.getString("role"), o.text("content"),
        o.text("senderId"), o.text("image"), o.optLong("created", now()), o.text("status", "complete"), o.text("error")) }
}
data class Memory(val id: String = newId(), val friendId: String, val text: String, val category: String = "其他", val pinned: Boolean = false, val importance: Int = 3) {
    fun toJson() = json("id" to id, "friendId" to friendId, "text" to text, "category" to category, "pinned" to pinned, "importance" to importance)
    companion object { fun from(o: JSONObject) = Memory(o.getString("id"), o.getString("friendId"), o.getString("text"), o.text("category", "其他"), o.optBoolean("pinned"), o.optInt("importance", 3)) }
}
data class Diary(val id: String = newId(), val friendId: String, val day: String = today(), val content: String) {
    fun toJson() = json("id" to id, "friendId" to friendId, "day" to day, "content" to content)
    companion object { fun from(o: JSONObject) = Diary(o.getString("id"), o.getString("friendId"), o.getString("day"), o.getString("content")) }
}
data class Anniversary(val id: String = newId(), val friendId: String, val title: String, val day: String) {
    fun toJson() = json("id" to id, "friendId" to friendId, "title" to title, "day" to day)
    companion object { fun from(o: JSONObject) = Anniversary(o.getString("id"), o.getString("friendId"), o.getString("title"), o.getString("day")) }
}
data class Comment(val id: String = newId(), val name: String, val text: String) {
    fun toJson() = json("id" to id, "name" to name, "text" to text)
    companion object { fun from(o: JSONObject) = Comment(o.text("id", newId()), o.text("name"), o.text("text")) }
}
data class Moment(
    val id: String = newId(), val authorId: String = "", val authorName: String = "我",
    val content: String, val image: String = "", val liked: Boolean = false,
    val comments: List<Comment> = emptyList(), val created: Long = now()
) {
    fun toJson() = json("id" to id, "authorId" to authorId, "authorName" to authorName, "content" to content,
        "image" to image, "liked" to liked, "comments" to arr(comments.map { it.toJson() }), "created" to created)
    companion object { fun from(o: JSONObject) = Moment(o.getString("id"), o.text("authorId"), o.text("authorName", "我"), o.text("content"),
        o.text("image"), o.optBoolean("liked"), o.objects("comments").map(Comment::from), o.optLong("created", now())) }
}
data class Profile(val name: String = "", val birthday: String = "", val bio: String = "记录一点生活，留住一些温柔。", val avatar: String = "", val cover: String = "", val tags: String = "日常 · 陪伴 · 小确幸") {
    val displayName: String get() = name.ifBlank { "我" }
    val zodiac: String get() = runCatching {
        val d = LocalDate.parse(birthday); val n = d.monthValue * 100 + d.dayOfMonth
        when(n) { in 120..218 -> "水瓶座"; in 219..320 -> "双鱼座"; in 321..419 -> "白羊座"; in 420..520 -> "金牛座";
            in 521..621 -> "双子座"; in 622..722 -> "巨蟹座"; in 723..822 -> "狮子座"; in 823..922 -> "处女座";
            in 923..1023 -> "天秤座"; in 1024..1122 -> "天蝎座"; in 1123..1221 -> "射手座"; else -> "摩羯座" }
    }.getOrDefault("")
    fun toJson() = json("name" to name, "birthday" to birthday, "bio" to bio, "avatar" to avatar, "cover" to cover, "tags" to tags)
    companion object { fun from(o: JSONObject) = Profile(o.text("name"), o.text("birthday"), o.text("bio"), o.text("avatar"), o.text("cover"), o.text("tags")) }
}
data class Provider(val id: String = newId(), val name: String = "DeepSeek", val baseUrl: String = "https://api.deepseek.com", val model: String = "deepseek-flash", val protocol: String = "openai", val vision: Boolean = false) {
    fun toJson() = json("id" to id, "name" to name, "baseUrl" to baseUrl, "model" to model, "protocol" to protocol, "vision" to vision)
    companion object { fun from(o: JSONObject) = Provider(o.getString("id"), o.getString("name"), o.getString("baseUrl"), o.getString("model"), o.text("protocol", "openai"), o.optBoolean("vision")) }
}
data class Usage(val id: String = newId(), val model: String, val kind: String, val input: Long, val output: Long, val created: Long = now()) {
    fun toJson() = json("id" to id, "model" to model, "kind" to kind, "input" to input, "output" to output, "created" to created)
    companion object { fun from(o: JSONObject) = Usage(o.getString("id"), o.text("model"), o.text("kind"), o.optLong("input"), o.optLong("output"), o.optLong("created", now())) }
}
data class Preferences(val theme: String = "system", val autoMemory: Boolean = false, val autoRead: Boolean = false, val profileDone: Boolean = false) {
    fun toJson() = json("theme" to theme, "autoMemory" to autoMemory, "autoRead" to autoRead, "profileDone" to profileDone)
    companion object { fun from(o: JSONObject) = Preferences(o.text("theme", "system"), o.optBoolean("autoMemory"), o.optBoolean("autoRead"), o.optBoolean("profileDone")) }
}
data class AppData(
    val friends: List<Friend> = emptyList(), val chats: List<Chat> = emptyList(), val messages: List<Message> = emptyList(),
    val memories: List<Memory> = emptyList(), val diaries: List<Diary> = emptyList(), val anniversaries: List<Anniversary> = emptyList(),
    val moments: List<Moment> = emptyList(), val providers: List<Provider> = listOf(Provider()), val activeProvider: String = "",
    val profile: Profile = Profile(), val preferences: Preferences = Preferences(), val usage: List<Usage> = emptyList(),
    val defaultArtworkVersion: Int = 1
) {
    val provider: Provider get() = providers.firstOrNull { it.id == activeProvider } ?: providers.first()
    fun toJson(): JSONObject = json("format" to "lumi.android", "version" to 1,
        "friends" to arr(friends.map { it.toJson() }), "chats" to arr(chats.map { it.toJson() }), "messages" to arr(messages.map { it.toJson() }),
        "memories" to arr(memories.map { it.toJson() }), "diaries" to arr(diaries.map { it.toJson() }), "anniversaries" to arr(anniversaries.map { it.toJson() }),
        "moments" to arr(moments.map { it.toJson() }), "providers" to arr(providers.map { it.toJson() }), "activeProvider" to activeProvider,
        "profile" to profile.toJson(), "preferences" to preferences.toJson(), "usage" to arr(usage.map { it.toJson() }), "defaultArtworkVersion" to defaultArtworkVersion)
    fun validated(): AppData {
        require(providers.isNotEmpty() && friends.size <= 500 && messages.size <= 100_000) { "备份记录数量超出范围" }
        fun unique(ids: List<String>) { require(ids.all { it.isNotBlank() } && ids.toSet().size == ids.size) { "备份存在重复或空 ID" } }
        unique(friends.map { it.id }); unique(chats.map { it.id }); unique(messages.map { it.id }); unique(providers.map { it.id })
        unique(memories.map { it.id }); unique(diaries.map { it.id }); unique(anniversaries.map { it.id }); unique(moments.map { it.id })
        val friendIds = friends.map { it.id }.toSet(); val chatIds = chats.map { it.id }.toSet()
        require(chats.all { it.members.isNotEmpty() && it.members.size <= 8 && it.members.distinct().size == it.members.size && it.members.all(friendIds::contains) }) { "会话引用的好友不存在" }
        require(messages.all { it.chatId in chatIds && it.role in listOf("user", "assistant") && (it.senderId.isBlank() || it.senderId in friendIds) && it.content.length <= 128_000 }) { "聊天记录格式错误" }
        require(memories.all { it.friendId in friendIds && it.text.length <= 4000 && it.importance in 1..5 } && diaries.all { it.friendId in friendIds } && anniversaries.all { it.friendId in friendIds }) { "记忆或日记引用错误" }
        require(friends.all { it.name.isNotBlank() && it.name.length <= 40 && it.persona.isNotBlank() && listOf(it.persona, it.style, it.background, it.taboos, it.greeting).all { s -> s.length <= 12000 } }) { "好友卡字段不符合要求" }
        require(profile.name.length <= 40 && (profile.birthday.isEmpty() || !LocalDate.parse(profile.birthday).isAfter(LocalDate.now()))) { "个人资料格式错误" }
        require(moments.all { it.authorId.isBlank() || it.authorId in friendIds }) { "朋友圈作者不存在" }
        require(anniversaries.all { runCatching { LocalDate.parse(it.day) }.isSuccess }) { "纪念日日期格式错误" }
        return this
    }
    companion object {
        fun from(o: JSONObject): AppData {
            require(o.text("format") == "lumi.android" && o.optInt("version") == 1) { "不支持的 Android 备份版本" }
            return AppData(o.objects("friends").map(Friend::from), o.objects("chats").map(Chat::from), o.objects("messages").map(Message::from),
                o.objects("memories").map(Memory::from), o.objects("diaries").map(Diary::from), o.objects("anniversaries").map(Anniversary::from),
                o.objects("moments").map(Moment::from), o.objects("providers").map(Provider::from), o.text("activeProvider"),
                Profile.from(o.optJSONObject("profile") ?: JSONObject()), Preferences.from(o.optJSONObject("preferences") ?: JSONObject()), o.objects("usage").map(Usage::from), o.optInt("defaultArtworkVersion", 0)).validated()
        }
    }
}

object MemoryRecall {
    fun terms(text: String): Set<String> {
        val words = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 2 }.toMutableSet()
        val chinese = text.filter { it.code in 0x3400..0x9fff }
        chinese.windowed(2).forEach(words::add)
        return words
    }
    fun recall(query: String, memories: List<Memory>, limit: Int = 6): List<Memory> {
        val queryTerms = terms(query)
        return memories.map { m -> m to terms(m.text).intersect(queryTerms).size }
            .filter { (m, n) -> m.pinned || n > 0 }
            .sortedByDescending { (m, n) -> n * 8 + m.importance * 2 + if (m.pinned) 12 else 0 }.take(limit).map { it.first }
    }
}
