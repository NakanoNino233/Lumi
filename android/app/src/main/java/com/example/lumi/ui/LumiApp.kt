package com.example.lumi.ui

import android.app.Activity
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.lumi.LumiModel
import androidx.core.view.WindowCompat

private data class Destination(val page: String, val tab: Int) {
    val key: String get() = page.ifBlank { "tab:$tab" }
}

@Composable fun LumiApp(model: LumiModel, speak: (String) -> Unit, share: (String) -> Unit) {
    val state = model.data
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var page by rememberSaveable { mutableStateOf("") }
    val history = rememberSaveable { arrayListOf<String>() }
    val screenState = key(model.dataEpoch) { rememberSaveableStateHolder() }
    var goingBack by remember { mutableStateOf(false) }
    val nav: (String) -> Unit = { if (it != page) { goingBack = false; history.add(page); page = it } }
    val back: () -> Unit = {
        goingBack = true
        if (!page.startsWith("chat:")) screenState.removeState(page)
        page = if(history.isNotEmpty()) history.removeAt(history.lastIndex) else ""
    }
    LaunchedEffect(model.dataEpoch) { if(model.dataEpoch > 0) { page = ""; history.clear(); tab = 0 } }
    val viewingMoments = state?.preferences?.profileDone == true && ((page.isBlank() && tab == 2) || page.startsWith("moments:"))
    LumiTheme(state?.preferences?.theme ?: "system", moments = viewingMoments) {
        val snack = remember { SnackbarHostState() }
        val window = (LocalView.current.context as? Activity)?.window
        val lightBackground = MaterialTheme.colorScheme.background.luminance() > .5f
        SideEffect { window?.let {
            WindowCompat.getInsetsController(it, it.decorView).apply {
                isAppearanceLightStatusBars = !viewingMoments && lightBackground
                isAppearanceLightNavigationBars = lightBackground
            }
        } }
        val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(model::previewBackup) }
        LaunchedEffect(model.notice) { model.notice?.let { snack.showSnackbar(it); model.dismissNotice() } }
        BackHandler(page.isNotBlank() || tab != 0) { if(page.isNotBlank()) back() else tab = 0 }
        Scaffold(containerColor=MaterialTheme.colorScheme.background,
            contentWindowInsets=if(viewingMoments) WindowInsets(0,0,0,0) else ScaffoldDefaults.contentWindowInsets,
            snackbarHost={SnackbarHost(snack)},
            topBar={ Column {
                if(page.isNotBlank() && state!=null && !viewingMoments) {
                    val title = when(page.substringBefore(':')) {
                        "chat" -> state.chats.find { it.id==page.substringAfter(':') }?.title ?: "聊天"
                        "friend" -> "好友资料"; "edit" -> "编辑好友"; "api" -> "API 配置"; "profile" -> "个人资料"
                        "memory" -> "记忆"; "diary" -> "日记"; "anniversary" -> "纪念日"; "usage" -> "用量统计"
                        "backup" -> "备份与恢复"; "group" -> "创建群聊"; "about" -> "关于 Lumi"; else -> "Lumi"
                    }
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    BackBar(title,back,action=if(page.startsWith("chat:")) {
                        { TextButton(onClick={
                            val id=page.substringAfter(':'); val chat=state.chats.find { it.id==id }
                            share(buildString { append("Lumi · ${chat?.title}\n\n"); state.messages.filter { it.chatId==id && it.content.isNotBlank() }.forEach { m ->
                                append(if(m.role=="user") state.profile.displayName else state.friends.find { it.id==m.senderId }?.name ?: chat?.title ?: "好友"); append("：\n${m.content}\n\n")
                            } })
                        }) { Text("分享") } }
                    } else null)
                }
                AnimatedVisibility(model.busy.isNotBlank(), enter=expandVertically(tween(180))+fadeIn(), exit=shrinkVertically(tween(180))+fadeOut()) { Column {
                    Text(model.busy+"…",Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=6.dp),fontSize=12.sp,color=MaterialTheme.colorScheme.primary)
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                } }
            } },
            bottomBar={ if(state!=null && state.preferences.profileDone && page.isBlank()) NavigationBar(containerColor=MaterialTheme.colorScheme.surface,tonalElevation=0.dp) {
                listOf("聊天" to "chat","好友" to "friends","朋友圈" to "moments","我的" to "me").forEachIndexed { i,(text,icon) ->
                    NavigationBarItem(selected=tab==i,onClick={goingBack=false;tab=i},icon={Glyph(icon,color=if(tab==i) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)},label={Text(text,fontSize=11.sp)})
                }
            } }
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding)) {
                AnimatedContent(targetState=Destination(page,tab), modifier=Modifier.fillMaxSize(), contentKey={it.key}, label="页面切换", transitionSpec={
                    if(initialState.page.isBlank() && targetState.page.isBlank()) {
                        fadeIn(tween(180)) togetherWith fadeOut(tween(120))
                    } else {
                        val direction = if(goingBack) -1 else 1
                        (fadeIn(tween(220)) + slideInHorizontally(tween(220)){ it / 12 * direction }) togetherWith
                            (fadeOut(tween(140)) + slideOutHorizontally(tween(180)){ -it / 20 * direction })
                    }
                }) { destination -> screenState.SaveableStateProvider(destination.key) {
                val page = destination.page
                val destinationTab = destination.tab
                when {
                    model.bootError!=null && state==null -> Column(Modifier.fillMaxSize().padding(30.dp),verticalArrangement=Arrangement.Center) {
                        Text("数据需要恢复",style=MaterialTheme.typography.headlineMedium); Spacer(Modifier.height(16.dp)); Text(model.bootError!!)
                        Spacer(Modifier.height(20.dp)); Button(onClick={restore.launch(arrayOf("application/zip","application/json","application/octet-stream"))}) { Text("选择备份") }
                    }
                    state==null -> Column(Modifier.align(Alignment.Center),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(18.dp)) {
                        LumiLogo(72.dp); Text("Lumi",fontSize=30.sp,fontWeight=FontWeight.SemiBold); CircularProgressIndicator(Modifier.size(24.dp),strokeWidth=2.dp)
                    }
                    !state.preferences.profileDone -> ProfileScreen(model,state.profile,onSaved={model.skipProfile()},welcome=true)
                    page.isBlank() -> when(destinationTab) {
                        0 -> HomeScreen(model,state,nav)
                        1 -> FriendsScreen(model,state,nav)
                        2 -> MomentsScreen(model,state,openFriend={nav("moments:$it")},onBack={goingBack=true;tab=0})
                        else -> MeScreen(model,state,nav)
                    }
                    else -> {
                        val id=page.substringAfter(':',"")
                        when(page.substringBefore(':')) {
                            "chat" -> state.chats.find { it.id==id }?.let { ChatScreen(model,state,it,speak,nav) } ?: EmptyState("🌿","会话已移除","返回后选择其他会话")
                            "friend" -> state.friends.find { it.id==id }?.let { FriendScreen(model,state,it,nav,back) }
                            "moments" -> state.friends.find { it.id==id }?.let { MomentsScreen(model,state,openFriend={nav("moments:$it")},onBack=back,friendId=id) }
                            "edit" -> FriendEditorScreen(model,state.friends.find { it.id==id },back)
                            "api" -> ApiScreen(model,state)
                            "profile" -> ProfileScreen(model,state.profile,onSaved=back)
                            "memory" -> MemoryScreen(model,state,id)
                            "diary" -> DiaryScreen(model,state,id)
                            "anniversary" -> AnniversaryScreen(model,state,id)
                            "group" -> GroupScreen(model,state) { nav("chat:$it") }
                            "usage" -> UsageScreen(state)
                            "backup" -> BackupScreen(model,state)
                            "about" -> AboutScreen()
                        }
                    }
                }
                } }
            }
        }
        model.pendingRestore?.let { incoming -> AlertDialog(onDismissRequest=model::cancelRestore,title={Text("恢复这份备份？")},text={Text("已验证：${incoming.friends.size} 位好友、${incoming.messages.size} 条消息、${incoming.memories.size} 条记忆、${incoming.moments.size} 条动态。\n\n恢复将替换本机当前资料，替换前会在应用内部保存一份回滚副本。API Key 需要重新检查或填写。iOS 备份仅迁移受支持的核心文本资料。")},
            confirmButton={TextButton(onClick=model::confirmRestore,enabled=!model.restoring){Text("恢复")}},dismissButton={TextButton(onClick=model::cancelRestore,enabled=!model.restoring){Text("取消")}}) }
        if(model.restoring) Dialog(onDismissRequest={},properties=DialogProperties(dismissOnBackPress=false,dismissOnClickOutside=false)) {
            Surface(shape=MaterialTheme.shapes.large) { Row(Modifier.padding(28.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(18.dp)) {
                CircularProgressIndicator(Modifier.size(24.dp),strokeWidth=2.dp); Text("正在恢复资料…")
            } }
        }
    }
}
