package com.example.lumi

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import androidx.lifecycle.ViewModelProvider
import com.example.lumi.data.Provider

@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    @Test fun navigationAndOfflineChatPersist() {
        compose.waitUntil(15000){compose.onAllNodesWithText("先逛逛，稍后填写").fetchSemanticsNodes().isNotEmpty()||compose.onAllNodesWithText("聊聊今天").fetchSemanticsNodes().isNotEmpty()}
        if(compose.onAllNodesWithText("先逛逛，稍后填写").fetchSemanticsNodes().isNotEmpty())compose.onNodeWithText("先逛逛，稍后填写").performScrollTo().performClick()
        compose.onNodeWithText("聊聊今天").assertIsDisplayed()
        compose.onNodeWithText("好友",useUnmergedTree=true).performClick()
        compose.onNodeWithText("你的好友").assertIsDisplayed()
        compose.onNodeWithText("大肥鱼",substring=false).performClick()
        compose.onNodeWithText("开始聊天").performClick()
        compose.onNodeWithText("说点什么…").performTextInput("这是一次离线安装验证")
        compose.onNodeWithContentDescription("发送").performClick()
        compose.onNodeWithText("这是一次离线安装验证").assertIsDisplayed()
        lateinit var model:LumiModel
        compose.runOnUiThread{model=ViewModelProvider(compose.activity)[LumiModel::class.java]}
        val payload="data: {\"choices\":[{\"delta\":{\"content\":\"模拟服务已收到你的问候。\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: {\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":20},\"choices\":[]}\n\ndata: [DONE]\n\n"
        MockServer(payload).use{server->
            val provider=Provider(name="自动测试",baseUrl=server.url,model="mock")
            compose.runOnUiThread{model.saveProvider(provider,"test-not-a-real-key")}
            compose.waitUntil(10000){model.data?.provider?.id==provider.id&&model.busy.isBlank()&&model.generatingChat==null}
            compose.runOnUiThread{model.regenerate(model.data!!.chats.last().id)}
            compose.waitUntil(15000){compose.onAllNodesWithText("模拟服务已收到你的问候。").fetchSemanticsNodes().isNotEmpty()&&model.generatingChat==null}
            compose.onNodeWithText("模拟服务已收到你的问候。").assertIsDisplayed()
        }
        compose.activityRule.scenario.recreate()
        compose.waitUntil(10000){compose.onAllNodesWithText("这是一次离线安装验证").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("朋友圈",useUnmergedTree=true).performClick()
        compose.onNodeWithTag("moments.feed").assertIsDisplayed()
        compose.onNodeWithText("我的",useUnmergedTree=true).performClick()
        compose.onNodeWithText("我的小天地").assertIsDisplayed()
        compose.waitUntil(10000){runCatching{com.example.lumi.data.LocalStore(compose.activity).load()==model.data}.getOrDefault(false)}
    }
}
