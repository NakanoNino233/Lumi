package com.example.lumi.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.security.KeyStore
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import java.util.zip.ZipEntry
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

fun InputStream.readBounded(limit: Int): ByteArray {
    val out = ByteArrayOutputStream(); val buffer = ByteArray(8192)
    while (true) { val n = read(buffer); if (n < 0) break; require(out.size() + n <= limit) { "文件过大，请选择较小的文件" }; out.write(buffer, 0, n) }
    return out.toByteArray()
}

class LocalStore(private val context: Context) {
    private val file = AtomicFile(File(context.filesDir, "lumi.json"))
    @Synchronized fun load(): AppData? {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        val stored = file.openRead().use { AppData.from(JSONObject(String(it.readBounded(80_000_000), Charsets.UTF_8))) }
        val upgraded = upgradeDefaultArtwork(stored)
        if (upgraded != stored) save(upgraded)
        return upgraded
    }
    @Synchronized fun save(data: AppData) {
        val bytes = data.toJson().toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= 80_000_000) { "本机资料超过 80 MB，请导出备份并清理旧会话" }
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (e: Exception) { file.failWrite(stream); throw e }
    }
    private fun daughterPersona(): String = context.assets.open("prompts/DeepSeekDaughter.txt").bufferedReader().use { it.readText() }
    private fun daughterAvatar(): String {
        val bitmap = BitmapFactory.decodeResource(context.resources, com.example.lumi.R.drawable.daughter_avatar)
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out); bitmap.recycle()
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        }
    }
    private fun upgradeDefaultArtwork(data: AppData): AppData {
        if (data.defaultArtworkVersion >= 1) return data
        val persona = daughterPersona().replace("\r\n", "\n").trim()
        val avatar by lazy { daughterAvatar() }
        val friends = data.friends.map { friend ->
            // Match the old bundled character, preserving edited avatars and other friends.
            val legacyDefault = friend.name == "大肥鱼" && friend.emoji == "🐋" && friend.avatar.isBlank() &&
                friend.persona.replace("\r\n", "\n").trim() == persona &&
                friend.style == "短句、自然口语，聪明嘴硬，有主见，也尊重你的生活。" &&
                friend.background == "DeepSeek 小鲸鱼，虚构 AI 女儿。角色背景中的爸爸是梁文锋；当前用户的身份、生日与资料卡分开处理。" &&
                friend.taboos.isBlank() && friend.greeting.isBlank()
            if (legacyDefault) friend.copy(avatar = avatar) else friend
        }
        return data.copy(friends = friends, defaultArtworkVersion = 1)
    }
    fun seed(): AppData {
        val friend = Friend(name = "大肥鱼", persona = daughterPersona(), emoji = "🐋", avatar = daughterAvatar(), style = "短句、自然口语，聪明嘴硬，有主见，也尊重你的生活。",
            background = "DeepSeek 小鲸鱼，虚构 AI 女儿。角色背景中的爸爸是梁文锋；当前用户的身份、生日与资料卡分开处理。", pinned = true)
        return AppData(friends = listOf(friend))
    }
}

/** Credentials stay in noBackupFilesDir and are encrypted with a non-exportable Android Keystore key. */
class SecretStore(context: Context) {
    private val root = File(context.noBackupFilesDir, "credentials").apply { mkdirs() }
    private val alias = "lumi.api.credentials.v1"
    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun file(id: String): AtomicFile { require(id.matches(Regex("[a-zA-Z0-9-]{1,80}"))); return AtomicFile(File(root, id)) }
    fun get(id: String): String {
        val f = file(id); if (!f.baseFile.exists()) return ""
        val bytes = f.readFully(); require(bytes.size > 12) { "密钥文件损坏，请重新填写" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
    fun set(id: String, value: String) {
        val f = file(id)
        if (value.isBlank()) { f.delete(); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(value.trim().toByteArray(Charsets.UTF_8))
        val out = f.startWrite(); try { out.write(encrypted); f.finishWrite(out) } catch (e: Exception) { f.failWrite(out); throw e }
    }
}

object Images {
    fun fromUri(context: Context, uri: Uri): String = context.contentResolver.openInputStream(uri)!!.use { normalize(it.readBounded(15_000_000)) }
    fun normalize(bytes: ByteArray): String {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }; BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 1..16000 && bounds.outHeight in 1..16000 && bounds.outWidth.toLong() * bounds.outHeight <= 100_000_000) { "无法读取图片或图片尺寸过大" }
        val options = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 1400) }
        val original = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: error("无法读取图片")
        val ratio = minOf(1f, 1200f / maxOf(original.width, original.height))
        val scaled = if (ratio < 1f) Bitmap.createScaledBitmap(original, (original.width * ratio).toInt().coerceAtLeast(1), (original.height * ratio).toInt().coerceAtLeast(1), true) else original
        val out = ByteArrayOutputStream(); scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
        if (scaled !== original) scaled.recycle(); original.recycle()
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
    fun validate(base64: String) {
        if (base64.isBlank()) return
        require(base64.length <= 7_000_000) { "图片过大" }
        val bytes = Base64.decode(base64, Base64.DEFAULT)
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }; BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        require(options.outWidth in 1..8192 && options.outHeight in 1..8192 && options.outWidth.toLong() * options.outHeight <= 20_000_000) { "备份包含无效图片" }
    }
}

object BackupCodec {
    fun encode(data: AppData): ByteArray = ByteArrayOutputStream().also { out ->
        ZipOutputStream(out).use { zip -> zip.putNextEntry(ZipEntry("lumi-android.json")); zip.write(data.toJson().toString().toByteArray(Charsets.UTF_8)); zip.closeEntry() }
    }.toByteArray()
    fun decode(bytes: ByteArray): AppData {
        require(bytes.size <= 50_000_000) { "备份压缩包不能超过 50 MB" }
        var snapshot: ByteArray? = null
        if (bytes.size >= 2 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte()) {
            ZipInputStream(bytes.inputStream()).use { zip ->
                var total = 0; var entries = 0
                while (true) {
                    val entry = zip.nextEntry ?: break
                    require(++entries <= 5001) { "备份条目过多" }
                    val content = zip.readBounded(80_000_000 - total); total += content.size
                    require(total <= 80_000_000) { "备份展开后过大" }
                    if (entry.name in setOf("lumi-android.json", "lumi.json")) { require(snapshot == null) { "备份包含多个数据文件" }; snapshot = content }
                    zip.closeEntry()
                }
            }
        } else snapshot = bytes
        val obj = JSONObject(String(requireNotNull(snapshot) { "找不到 Lumi 备份数据" }, Charsets.UTF_8))
        val data = if (obj.text("format") == "lumi.android") AppData.from(obj) else fromIos(obj)
        (data.friends.flatMap { listOf(it.avatar, it.momentsCover) } + data.messages.map { it.image } + data.moments.map { it.image } + listOf(data.profile.avatar, data.profile.cover)).filter { it.isNotBlank() }.distinct().forEach(Images::validate)
        data.providers.forEach { com.example.lumi.network.Endpoint.resolve(it.baseUrl, it.protocol, com.example.lumi.BuildConfig.DEBUG) }
        return data.validated()
    }
    // Swift JSONEncoder's Date is seconds since 2001-01-01. Android uses Unix milliseconds.
    private fun date(o: JSONObject, key: String): Long = if (o.has(key) && !o.isNull(key)) ((o.optDouble(key) + 978307200.0) * 1000).toLong() else now()
    private fun fromIos(o: JSONObject): AppData {
        require(o.optInt("version") == 1 && o.has("lumiCharacters")) { "无法识别此备份" }
        val friends = o.objects("lumiCharacters").map { Friend.from(it).copy(created = date(it, "createdAt"), pinned = !it.isNull("pinnedAt")) }
        val chats = o.objects("conversations").map { Chat(it.getString("id"), listOf(it.getString("characterID")), it.text("title"), date(it, "createdAt")) }
        val messages = o.objects("messages").map { Message(it.getString("id"), it.getString("conversationID"), it.text("role"), visibleIosText(it.text("content")), created = date(it, "createdAt"), status = "complete") }
        val memories = o.objects("memoryFacts").map { Memory(it.getString("id"), it.getString("characterID"), it.text("text"), it.text("category", "其他"), it.optInt("pinOrder") > 0, it.optInt("importance", 3)) }
        val diaries = o.objects("diaryEntrys").map { Diary(it.getString("id"), it.getString("characterID"), it.text("day"), it.text("content")) }
        val providers = o.objects("providerConfigs").map { Provider(it.getString("id"), it.text("name"), it.text("baseURL"), it.text("modelName"), vision = it.optBoolean("supportsVision")) }.ifEmpty { listOf(Provider()) }
        val personal = o.optJSONObject("personalProfile") ?: JSONObject()
        val birth = personal.optJSONObject("birthday")?.let { "%04d-%02d-%02d".format(it.optInt("year"), it.optInt("month"), it.optInt("day")) }.orEmpty()
        val profile = Profile(name = personal.text("name"), birthday = birth, avatar = personal.text("avatarData"), cover = o.text("momentCoverData"))
        val anniversaries = o.objects("anniversarys").map { Anniversary(it.getString("id"), it.getString("characterID"), it.text("title"), java.time.Instant.ofEpochMilli(date(it, "date")).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toString()) }
        val moments = o.objects("momentPosts").map { post ->
            val comments = runCatching { JSONObject().put("c", org.json.JSONArray(String(Base64.decode(post.text("commentData"), Base64.DEFAULT), Charsets.UTF_8))).objects("c").map { Comment(it.text("id", newId()), it.text("authorName", "我"), it.text("text")) } }.getOrDefault(emptyList())
            Moment(post.getString("id"), post.text("authorID"), post.text("authorName", "我"), post.text("content"), liked = post.optBoolean("liked"), comments = comments, created = date(post, "createdAt"))
        }
        return AppData(friends, chats, messages, memories, diaries, anniversaries, moments, providers, profile = profile, preferences = Preferences(profileDone = true))
    }
    private fun visibleIosText(text: String) = com.example.lumi.network.visibleReply(text)
}
