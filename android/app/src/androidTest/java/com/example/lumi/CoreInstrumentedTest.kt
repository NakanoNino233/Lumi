package com.example.lumi

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.lumi.data.*
import com.example.lumi.network.*
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

@RunWith(AndroidJUnit4::class)
class CoreInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(): AppData {
        val f=Friend(name="测试好友",persona="一位虚构且友善的 AI 好友",greeting="你好",emoji="🌱")
        val chat=Chat(members=listOf(f.id),title=f.name)
        return AppData(friends=listOf(f),chats=listOf(chat),messages=listOf(Message(chatId=chat.id,role="user",content="周末一起聊书店")),
            memories=listOf(Memory(friendId=f.id,text="喜欢书店",pinned=true)),diaries=listOf(Diary(friendId=f.id,content="今天聊到书店")),
            anniversaries=listOf(Anniversary(friendId=f.id,title="初识",day="2026-11-16")),moments=listOf(Moment(content="今天的阳光很好",comments=listOf(Comment(name="我",text="真好")))),
            profile=Profile(name="测试用户",birthday="2000-01-01"),preferences=Preferences(profileDone=true))
    }
    @Test fun androidBackupRoundTripsEveryCoreRecord() {
        val source=fixture();val restored=BackupCodec.decode(BackupCodec.encode(source))
        assertEquals(source,restored)
    }
    @Test fun invalidBackupReferencesAreRejected() {
        val source=fixture().toJson();source.getJSONArray("messages").getJSONObject(0).put("chatId","missing")
        assertThrows(IllegalArgumentException::class.java){BackupCodec.decode(source.toString().toByteArray())}
    }
    @Test fun iosV1CoreTextDataMigrates() {
        val ios=json("version" to 1,"lumiCharacters" to arr(listOf(json("id" to "f", "name" to "旧好友", "personaPrompt" to "温暖的虚构 AI", "createdAt" to 0))),
            "conversations" to arr(listOf(json("id" to "c", "characterID" to "f", "title" to "旧聊天", "createdAt" to 0))),
            "messages" to arr(listOf(json("id" to "m", "conversationID" to "c", "role" to "user", "content" to "你好", "createdAt" to 0))),
            "personalProfile" to json("name" to "小林", "birthday" to json("year" to 2001,"month" to 2,"day" to 3)))
        val restored=BackupCodec.decode(ios.toString().toByteArray())
        assertEquals("旧好友",restored.friends.single().name);assertEquals("你好",restored.messages.single().content)
        assertEquals(978307200000L,restored.messages.single().created);assertEquals("2001-02-03",restored.profile.birthday)
    }
    @Test fun credentialsAreEncryptedAndNeverPartOfBackup() {
        val id="instrumentation-secret";val secret="test-secret-only-not-a-real-api-key"
        val store=SecretStore(context);store.set(id,secret)
        try {
            assertEquals(secret,store.get(id))
            val encrypted=java.io.File(context.noBackupFilesDir,"credentials/$id").readBytes()
            assertFalse(String(encrypted,Charsets.UTF_8).contains(secret))
            val encoded=fixture().toJson().toString();assertFalse(encoded.contains(secret));assertFalse(encoded.contains("apiKey"))
        } finally {store.set(id,"")}
    }
    @Test fun atomicLocalStorageRoundTripsAndSeedLoads() {
        val isolated=context.createDeviceProtectedStorageContext();val store=LocalStore(isolated)
        val data=fixture();store.save(data);assertEquals(data,store.load())
        val seeded = store.seed(); assertEquals("大肥鱼",seeded.friends.single().name)
        Images.validate(seeded.friends.single().avatar); assertTrue(seeded.friends.single().avatar.isNotBlank())
        assertEquals(seeded,BackupCodec.decode(BackupCodec.encode(seeded)))
        listOf(R.drawable.lumi_logo,R.drawable.daughter_moments_cover,R.drawable.lumi_icon_dawn,R.drawable.lumi_icon_night,R.drawable.lumi_icon_ocean).forEach { resource ->
            val bitmap = android.graphics.BitmapFactory.decodeResource(context.resources,resource)
            assertNotNull("Bundled artwork must decode",bitmap); bitmap.recycle()
        }
        assertNotNull(context.packageManager.getApplicationIcon(context.applicationInfo))
    }
    @Test fun legacyDefaultAvatarMigratesOnceAndPreservesRecords() {
        val isolated = context.createDeviceProtectedStorageContext()
        val store = LocalStore(isolated)
        val source = fixture()
        val bundled = store.seed().friends.single()
        val oldFriend = bundled.copy(id = source.friends.single().id, avatar = "", affection = 37, created = 1234L)
        val legacy = source.copy(friends = listOf(oldFriend), defaultArtworkVersion = 0)
        store.save(legacy)
        // Old installs and backups have no migration marker at all.
        val oldJson = legacy.toJson().apply { remove("defaultArtworkVersion") }
        java.io.File(isolated.filesDir, "lumi.json").writeText(oldJson.toString(), Charsets.UTF_8)
        val upgraded = requireNotNull(store.load())
        Images.validate(upgraded.friends.single().avatar)
        assertTrue(upgraded.friends.single().avatar.isNotBlank())
        assertEquals(legacy.copy(friends = listOf(oldFriend.copy(avatar = bundled.avatar)), defaultArtworkVersion = 1), upgraded)
        assertEquals(upgraded, LocalStore(isolated).load())
        assertEquals(upgraded, BackupCodec.decode(BackupCodec.encode(upgraded)))
        // Choosing an emoji after upgrading remains a deliberate user choice.
        val cleared = upgraded.copy(friends = listOf(oldFriend))
        store.save(cleared)
        assertEquals(cleared, store.load())
        val customFriends = listOf(oldFriend.copy(avatar = bundled.avatar), oldFriend.copy(emoji = "🐈"),
            oldFriend.copy(name = "我的好友"), oldFriend.copy(persona = "用户自己创建的人设"))
        customFriends.forEach { custom ->
            val customData = legacy.copy(friends = listOf(custom))
            store.save(customData)
            assertEquals(customData.copy(defaultArtworkVersion = 1), store.load())
        }
    }
    @Test fun friendMomentsCoversRoundTripAndRejectInvalidImages() {
        val image = LocalStore(context).seed().friends.single().avatar
        val original = fixture().let { it.copy(friends = it.friends.map { f -> f.copy(momentsCover = image) }, profile = it.profile.copy(cover = image)) }
        assertEquals(original, BackupCodec.decode(BackupCodec.encode(original)))
        val old = original.toJson().apply { getJSONArray("friends").getJSONObject(0).remove("momentsCover") }
        assertEquals("", AppData.from(old).friends.single().momentsCover)
        val invalid = original.copy(friends = original.friends.map { it.copy(momentsCover = "not-an-image") })
        assertThrows(IllegalArgumentException::class.java) { BackupCodec.decode(BackupCodec.encode(invalid)) }
    }
    @Test fun openAiStreamingCapturesUsageAfterFinishAndUnicode() = runBlocking {
        val events=listOf("{\"choices\":[{\"delta\":{\"content\":\"你好，\"}}]}","{\"choices\":[{\"delta\":{\"content\":\"世界🌿\"}}]}","{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}","{\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":7}}","[DONE]")
        MockServer(events.joinToString(""){"data: $it\r\n\r\n"}).use{server->
            val parts=mutableListOf<String>();val result=LlmCall().run(Provider(baseUrl=server.url,model="mock"),"test-key",listOf(Turn("user","你好")),onDelta={parts.add(it)})
            assertEquals("你好，世界🌿",result.text);assertEquals(12L,result.input);assertEquals(7L,result.output)
            assertEquals(result.text,parts.joinToString(""));assertTrue(server.request.get().contains("\"role\":\"user\""))
        }
    }
    @Test fun anthropicStreamingAndHeadersWork() = runBlocking {
        val events=listOf("{\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":9}}}","{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"你好\"}}","{\"type\":\"message_delta\",\"usage\":{\"output_tokens\":4}}","{\"type\":\"message_stop\"}")
        MockServer(events.joinToString(""){"data: $it\n\n"}).use{server->
            val result=LlmCall().run(Provider(baseUrl=server.url,model="mock",protocol="anthropic"),"test-key",listOf(Turn("system","人设"),Turn("user","你好")))
            assertEquals("你好",result.text);assertEquals(9L,result.input);assertEquals(4L,result.output)
            assertTrue(server.headers.get().lowercase().contains("x-api-key: test-key"));assertTrue(server.request.get().contains("\"system\":\"人设\""))
        }
    }
    @Test fun failedAndTruncatedRequestsAreReported() = runBlocking {
        MockServer("",status=401).use{server->
            try { LlmCall().run(Provider(baseUrl=server.url,model="mock"),"test-key",listOf(Turn("user","你好")));fail("Expected HTTP error") }
            catch(e:IllegalStateException){assertTrue(e.message!!.contains("401"));assertFalse(e.message!!.contains("test-key"))}
        }
        MockServer("data: {\"choices\":[{\"delta\":{\"content\":\"部分回复\"}}]}\n\n").use{server->
            try {LlmCall().run(Provider(baseUrl=server.url,model="mock"),"test-key",listOf(Turn("user","你好")));fail("Expected truncation")}
            catch(e:IllegalArgumentException){assertTrue(e.message!!.contains("中断"))}
        }
    }
}

internal class MockServer(private val body:String,private val status:Int=200,private val responseGate:java.util.concurrent.CountDownLatch?=null):AutoCloseable {
    private val server=ServerSocket(0,1,InetAddress.getByName("127.0.0.1"))
    val request=AtomicReference("");val headers=AtomicReference("")
    val url="http://127.0.0.1:${server.localPort}/v1"
    private val worker=thread(isDaemon=true,name="lumi-mock"){runCatching{server.accept().use{socket->
        socket.soTimeout=10000;val input=socket.getInputStream();val header=StringBuilder()
        while(!header.endsWith("\r\n\r\n")){val byte=input.read();if(byte<0)break;header.append(byte.toChar());check(header.length<65536)}
        headers.set(header.toString());val length=Regex("Content-Length: (\\d+)",RegexOption.IGNORE_CASE).find(header)?.groupValues?.get(1)?.toInt()?:0
        val content=ByteArray(length);var offset=0;while(offset<length){val n=input.read(content,offset,length-offset);if(n<0)break;offset+=n};request.set(String(content,Charsets.UTF_8))
        responseGate?.await(10,java.util.concurrent.TimeUnit.SECONDS)
        val bytes=body.toByteArray(Charsets.UTF_8);val output=socket.getOutputStream()
        output.write("HTTP/1.1 $status Test\r\nContent-Type: text/event-stream; charset=utf-8\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
        bytes.asList().chunked(3).forEach{piece->output.write(piece.toByteArray());output.flush()}
    }}}
    override fun close(){server.close();worker.join(1000)}
}
