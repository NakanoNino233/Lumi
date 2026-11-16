package com.example.lumi

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.lumi.data.*
import com.example.lumi.ui.LumiApp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class MomentsFlowTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(context.getExternalFilesDir(null), "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
    @Test fun personalAndFriendCoversAndFeedsStaySeparate() {
        val store = LocalStore(context)
        val daughter = store.seed().friends.single().copy(id = "daughter-test")
        val other = Friend(id = "other-test", name = "另一位好友", persona = "虚构的读书好友", emoji = "🌱")
        val sample = context.resources.openRawResource(R.drawable.lumi_sticker_00).use { Images.normalize(it.readBytes()) }
        val custom = context.resources.openRawResource(R.drawable.lumi_icon_ocean).use { Images.normalize(it.readBytes()) }
        val fixture = AppData(friends = listOf(daughter, other),
            moments = listOf(
                Moment(id = "daughter-post", authorId = daughter.id, authorName = daughter.name, content = "今天也要好好吃饭。", image = sample, liked = true,
                    comments = listOf(Comment(name = "大肥鱼", text = "把日常慢慢记下来。")), created = now() - 31 * 60_000),
                Moment(id = "my-post", content = "给今天留一点小小的纪念。", created = now() - 90 * 60_000),
                Moment(id = "other-post", authorId = other.id, authorName = other.name, content = "读到一本喜欢的书。", created = now() - 120 * 60_000)),
            profile = Profile(name = "我的日常", avatar = daughter.avatar), preferences = Preferences(theme = "dark", profileDone = true))
        store.save(fixture)
        val viewModels = ViewModelStore()
        lateinit var model: LumiModel
        compose.runOnUiThread { model = ViewModelProvider(viewModels, ViewModelProvider.AndroidViewModelFactory.getInstance(context.applicationContext as Application))[LumiModel::class.java] }
        try {
            compose.setContent { LumiApp(model, {}, {}) }
            compose.waitUntil(15000) { model.data != null }
            compose.onNodeWithText("朋友圈", useUnmergedTree = true).performClick()
            compose.onNodeWithTag("moments.cover.personal").assertIsDisplayed()
            compose.onNodeWithTag("moments.cover.daughter").assertDoesNotExist()
            screenshot("moments-overview-dark")
            compose.onNodeWithTag("moments.open.${daughter.id}").performClick()
            compose.onNodeWithTag("moments.cover.daughter").assertIsDisplayed()
            compose.onNodeWithTag("moments.cover.personal").assertDoesNotExist()
            compose.onNodeWithText("今天也要好好吃饭。").assertIsDisplayed()
            compose.onNodeWithText("给今天留一点小小的纪念。").assertDoesNotExist()
            screenshot("moments-daughter-dark")
            compose.onNodeWithContentDescription("动态图片").performClick()
            compose.onNodeWithContentDescription("图片大图").assertIsDisplayed()
            compose.onNodeWithContentDescription("图片大图").performTouchInput { doubleClick() }
            screenshot("audit-image-preview")
            compose.onNodeWithText("关闭",substring=false).performClick()
            compose.onNodeWithTag("moments.actions.daughter-post").performClick()
            compose.onNodeWithText("取消点赞").performClick()
            compose.runOnIdle { assertFalse(model.data!!.moments.first { it.id == "daughter-post" }.liked) }
            compose.onNodeWithTag("moments.actions.daughter-post").performClick()
            compose.onNodeWithText("评论", substring = false).performClick()
            compose.onNodeWithText("写评论…").performTextInput("封面区分测试")
            compose.onNodeWithText("发送", substring = false).performClick()
            compose.waitUntil(5000) { model.data!!.moments.first { it.id == "daughter-post" }.comments.any { it.text == "封面区分测试" } }
            compose.runOnUiThread { model.saveMomentsCover(custom, daughter.id) }
            compose.onNodeWithTag("moments.cover.friend.${daughter.id}").assertIsDisplayed()
            compose.onNodeWithTag("moments.cover.daughter").assertDoesNotExist()
            compose.runOnIdle { assertEquals("", model.data!!.profile.cover); assertEquals("", model.data!!.friends.first { it.id == other.id }.momentsCover) }
            compose.runOnUiThread { model.saveMomentsCover("", daughter.id); model.saveMomentsCover(custom) }
            compose.onNodeWithTag("moments.cover.daughter").assertIsDisplayed()
            compose.onNodeWithContentDescription("返回").performClick()
            compose.onNodeWithTag("moments.cover.personal").assertIsDisplayed()
            compose.onNodeWithContentDescription("我的朋友圈封面").assertIsDisplayed()
            compose.onNodeWithTag("moments.cover.daughter").assertDoesNotExist()
            compose.onNodeWithContentDescription("朋友圈设置").performClick()
            compose.onNodeWithText("好友朋友圈", substring = false).performClick()
            compose.onNode(hasText(other.name, substring = false) and hasAnyAncestor(isDialog())).performClick()
            compose.onNodeWithTag("moments.cover.friend.default").assertIsDisplayed()
            compose.onNodeWithText("读到一本喜欢的书。").assertIsDisplayed()
            compose.onNodeWithText("今天也要好好吃饭。").assertDoesNotExist()
            compose.onNodeWithContentDescription("返回").performClick()
            compose.onNodeWithText("好友", useUnmergedTree = true).performClick()
            compose.onNodeWithText(daughter.name, substring = false).performClick()
            compose.onNodeWithText("朋友圈", substring = false).performClick()
            compose.onNodeWithTag("moments.cover.daughter").assertIsDisplayed()
            // Allow the background atomic write to finish before reading through a new store.
            compose.waitUntil(5000) { runCatching { org.json.JSONObject(File(context.filesDir, "lumi.json").readText()).getJSONObject("profile").getString("cover") == custom }.getOrDefault(false) }
            val persisted = requireNotNull(store.load())
            assertEquals(custom, persisted.profile.cover)
            assertEquals("", persisted.friends.first { it.id == daughter.id }.momentsCover)
            assertEquals(persisted, BackupCodec.decode(BackupCodec.encode(persisted)))
        } finally { compose.runOnUiThread { viewModels.clear() } }
    }
}
