package com.example.lumi

import android.app.Application
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.lumi.data.*
import com.example.lumi.ui.LumiApp
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch

/** Run only on the dedicated LumiTest AVD: these tests intentionally replace fixture data. */
@RunWith(AndroidJUnit4::class)
class AuditRegressionTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun fixture(): AppData {
        val friend = LocalStore(context).seed().friends.single().copy(id="audit-friend",affection=50)
        val chat = Chat(id="audit-chat",members=listOf(friend.id),title=friend.name)
        return AppData(friends=listOf(friend),chats=listOf(chat),
            messages=listOf(Message(id="audit-user",chatId=chat.id,role="user",content="你好"),
                Message(id="audit-original",chatId=chat.id,role="assistant",senderId=friend.id,content="需要保留的原回复")),
            preferences=Preferences(profileDone=true))
    }
    private fun withModel(fixture: AppData = fixture(), action: (LumiModel) -> Unit) {
        LocalStore(context).save(fixture)
        val models = ViewModelStore()
        lateinit var model: LumiModel
        compose.runOnUiThread { model=ViewModelProvider(models,ViewModelProvider.AndroidViewModelFactory.getInstance(context.applicationContext as Application))[LumiModel::class.java] }
        compose.waitUntil(10000) { model.data!=null }
        assertEquals(fixture,model.data)
        try { action(model) } finally {
            compose.waitUntil(15000) { model.generatingChat==null && model.busy.isBlank() }
            // Finish pending disk writes before releasing the isolated model.
            try {
                compose.waitUntil(10000) { runCatching { LocalStore(context).load()==model.data }.getOrDefault(false) }
            } catch(e: Exception) {
                File(context.cacheDir,"audit-expected.json").writeText(model.data!!.toJson().toString())
                throw e
            } finally { compose.runOnUiThread { models.clear() } }
        }
    }
    private fun response(text: String) = "data: " + json("choices" to arr(listOf(json("delta" to json("content" to text))))).toString() + "\n\ndata: [DONE]\n\n"
    private fun configure(model:LumiModel,server:MockServer) {
        compose.runOnUiThread { model.saveProvider(Provider(baseUrl=server.url,model="mock",name="测试服务"),"not-a-real-key") }
        compose.waitUntil(10000) { model.busy.isBlank() }
    }
    private fun screenshot(name:String) {
        compose.waitForIdle()
        val bitmap=InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(context.getExternalFilesDir(null),"$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
        bitmap.recycle()
    }

    @Test fun retryKeepsOriginalUntilSuccessAndEditorPreservesLiveFields() = withModel { model ->
        val oldFriend=model.data!!.friends.single()
        compose.runOnUiThread { model.regenerate("audit-chat") }
        compose.waitUntil(10000) { model.generatingChat==null }
        assertTrue(model.data!!.messages.any { it.id=="audit-original" })
        MockServer("",status=401).use { server ->
            configure(model,server)
            compose.runOnUiThread { model.regenerate("audit-chat") }
            compose.waitUntil(10000) { model.generatingChat==null }
            assertTrue(model.data!!.messages.any { it.id=="audit-original" })
        }
        MockServer(response("新的完整回复<meta affection_delta=\"3\">" )).use { server ->
            configure(model,server)
            compose.runOnUiThread { model.regenerate("audit-chat") }
            compose.waitUntil(10000) { model.generatingChat==null }
            assertFalse(model.data!!.messages.any { it.id=="audit-original" })
            assertEquals("新的完整回复",model.data!!.messages.last().content)
            assertFalse(server.request.get().contains("需要保留的原回复"))
        }
        compose.runOnUiThread {
            model.pinFriend(oldFriend.id)
            model.saveMomentsCover(oldFriend.avatar,oldFriend.id)
            assertTrue(model.saveFriend(oldFriend.copy(name="改名后的好友")))
        }
        val updated=model.data!!.friends.single()
        assertEquals(53,updated.affection)
        assertEquals(!oldFriend.pinned,updated.pinned)
        assertEquals(oldFriend.avatar,updated.momentsCover)
        assertEquals(updated.name,model.data!!.chats.single().title)
    }

    @Test fun inFlightFriendOperationsCannotCreateOrphanRecords() = withModel { model ->
        val gate=CountDownLatch(1)
        MockServer(response("今天过得很好。"),responseGate=gate).use { server ->
            configure(model,server)
            compose.runOnUiThread { model.generateMoment("audit-friend") }
            compose.waitUntil(10000) { server.request.get().isNotBlank() }
            compose.runOnUiThread { assertFalse(model.deleteFriend("audit-friend")) }
            gate.countDown()
            compose.waitUntil(10000) { model.busy.isBlank() }
            assertEquals(1,model.data!!.moments.size)
            compose.runOnUiThread { assertTrue(model.deleteFriend("audit-friend")) }
            assertTrue(model.data!!.moments.isEmpty())
            model.data!!.validated()
        }
    }

    @Test fun restoreBlocksEditsAndReplacesPendingWritesAtomically() = withModel { model ->
        val incoming=fixture().let { it.copy(profile=Profile(name="恢复后的资料"),messages=it.messages+Message(id="unfinished",chatId="audit-chat",role="assistant",senderId="audit-friend",content="未完成的回复",status="generating")) }
        val replacement=incoming.copy(messages=incoming.messages.map { if(it.status=="generating") it.copy(status="interrupted",error="上次生成被中断，可重新生成") else it })
        val file=File(context.cacheDir,"audit-restore.zip").apply { writeBytes(BackupCodec.encode(incoming)) }
        compose.runOnUiThread { model.previewBackup(Uri.fromFile(file)) }
        compose.waitUntil(10000) { model.pendingRestore!=null && model.busy.isBlank() }
        compose.runOnUiThread {
            repeat(12) { model.postMoment("旧数据的待写入动态 $it") }
            model.confirmRestore()
            assertTrue(model.restoring)
            model.postMoment("恢复途中不应写入")
        }
        compose.waitUntil(15000) { model.dataEpoch==1 && model.busy.isBlank() }
        assertEquals(replacement,model.data)
        assertEquals(replacement,LocalStore(context).load())
        assertEquals(12,BackupCodec.decode(File(context.filesDir,"before-restore.zip").readBytes()).moments.size)
        file.delete()
    }

    @Test fun draftsSearchAndReadingPositionSurviveNavigation() {
        val base=fixture()
        val messages=(0..45).map { i -> Message(id="history-$i",chatId="audit-chat",role=if(i%2==0)"user" else "assistant",senderId=if(i%2==0)"" else "audit-friend",content="第 $i 条历史消息，记录今天的日常。",created=now()+i) }
        withModel(base.copy(messages=messages)) { model ->
            compose.setContent { LumiApp(model,{},{}) }
            compose.onNodeWithText("好友",useUnmergedTree=true).performClick()
            compose.onNodeWithTag("friends.search").performTextInput("大肥")
            compose.onNodeWithText("聊天",useUnmergedTree=true).performClick()
            compose.onNodeWithText("好友",useUnmergedTree=true).performClick()
            compose.onNodeWithTag("friends.search").assertTextContains("大肥")
            compose.onNodeWithText("大肥鱼",substring=false).performClick()
            compose.onNodeWithText("开始聊天").performClick()
            compose.onNodeWithText("说点什么…").performTextInput("这段草稿还没发")
            compose.onNodeWithContentDescription("好友记忆").performClick()
            compose.onNodeWithContentDescription("返回").performClick()
            compose.onNode(hasSetTextAction()).assertTextContains("这段草稿还没发")
            val gate=CountDownLatch(1)
            MockServer(response("翻阅历史期间收到的新回复。"),responseGate=gate).use { server ->
            configure(model,server)
            compose.onNodeWithContentDescription("发送").performClick()
            compose.waitUntil(10000) { server.request.get().isNotBlank() }
            compose.onNodeWithTag("chat.messages").performTouchInput { swipeDown() }
            compose.onNodeWithText("↓ 回到最新消息").assertIsDisplayed()
            screenshot("audit-chat-reading")
            gate.countDown()
            compose.waitUntil(10000) { model.generatingChat==null }
            compose.onNodeWithText("↓ 回到最新消息").assertIsDisplayed()
            compose.onNodeWithText("↓ 回到最新消息").performClick()
            compose.onNodeWithText("翻阅历史期间收到的新回复。").assertIsDisplayed()
            }
            compose.onNodeWithContentDescription("图片语音与表情").performClick()
            compose.onNodeWithContentDescription("语音输入").assertIsDisplayed()
            screenshot("audit-chat-tools")
            compose.onNodeWithContentDescription("返回").performClick()
            compose.onNodeWithContentDescription("返回").performClick()
            compose.onNodeWithTag("friends.search").assertTextContains("大肥")
            screenshot("audit-friends-search")
        }
    }

    @Test fun previewCacheReusesBitmapsAndBoundsImportedImages() = runBlocking {
        val bitmap=Bitmap.createBitmap(2400,1600,Bitmap.Config.ARGB_8888)
        val encoded=java.io.ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
        bitmap.recycle()
        val data=android.util.Base64.encodeToString(encoded,android.util.Base64.NO_WRAP)
        val first=ImageCache.load(data)!!
        assertTrue(maxOf(first.width,first.height)<=1200)
        assertSame(first,ImageCache.load(data))
    }
}
