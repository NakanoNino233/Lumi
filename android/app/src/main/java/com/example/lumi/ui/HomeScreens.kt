package com.example.lumi.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.lumi.BuildConfig
import com.example.lumi.LumiModel
import com.example.lumi.data.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Composable fun HomeScreen(model: LumiModel, state: AppData, nav: (String) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    var deleting by remember { mutableStateOf<Chat?>(null) }
    val lastMessages=remember(state.messages) { state.messages.associateBy { it.chatId } }
    val sorted=remember(state.chats,lastMessages) { state.chats.sortedByDescending { c -> lastMessages[c.id]?.created ?: c.created } }
    val matchingChats=remember(state.messages,search) { if(search.isBlank()) emptySet() else state.messages.filter { it.content.contains(search,true) }.map { it.chatId }.toSet() }
    val visible=sorted.filter { c -> search.isBlank() || c.title.contains(search,true) || c.id in matchingChats }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(horizontal=22.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item { PageHeading("聊聊今天",LocalDate.now().format(DateTimeFormatter.ofPattern("M月d日 · EEEE")),action={IconButton(onClick={nav("group")}){Glyph("plus",label="创建群聊")}}) }
        item {
            Surface(shape=RoundedCornerShape(26.dp),color=Green,onClick={state.friends.firstOrNull()?.let { nav("chat:${model.startChat(it)}") } ?: nav("edit:new")}) {
                Box(Modifier.fillMaxWidth().heightIn(min=174.dp).padding(24.dp)) {
                    Column(Modifier.padding(end=60.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                        Text("留一盏灯，等你来聊。",fontSize=21.sp,color=androidx.compose.ui.graphics.Color.White,fontWeight=FontWeight.SemiBold)
                        Text("把日常说给懂你的朋友听，\n让细碎的小事都有回音。",fontSize=13.sp,lineHeight=22.sp,color=androidx.compose.ui.graphics.Color(0xFFD2E2D6))
                        Text("开始一段对话  ↗",fontSize=12.sp,color=Gold,fontWeight=FontWeight.Medium)
                    }
                    Star(Modifier.align(Alignment.CenterEnd).size(56.dp)); Star(Modifier.align(Alignment.TopEnd).size(13.dp))
                }
            }
        }
        if(state.usage.isEmpty()) item { SheetCard(onClick={nav("api")}) { Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Glyph("settings",color=MaterialTheme.colorScheme.primary); Column(Modifier.weight(1f)) { Text("连接你的模型",fontWeight=FontWeight.SemiBold,fontSize=14.sp); Text("填写自己的 API Key，开启第一次聊天",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Glyph("arrow")
        } } }
        item { OutlinedTextField(search,{search=it},Modifier.fillMaxWidth(),placeholder={Text("搜索好友和聊天内容",fontSize=13.sp)},singleLine=true,shape=RoundedCornerShape(18.dp)) }
        item { SectionLabel("最近的对话", "${state.friends.size} 位好友") { nav("edit:new") } }
        if(sorted.isEmpty()) item {
            SheetCard { state.friends.firstOrNull()?.let { f -> Row(Modifier.fillMaxWidth().clickable{nav("chat:${model.startChat(f)}")},verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                Avatar(f.emoji,f.avatar); Column(Modifier.weight(1f)) { Text(f.name,fontWeight=FontWeight.SemiBold); Text("第一次见面，从一句你好开始。",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Glyph("arrow")
            } } ?: EmptyState("🌱","从一位新朋友开始","创建角色后，就可以在这里聊天", "添加好友") { nav("edit:new") } }
        }
        items(visible,key={it.id}) { chat ->
            val friend=state.friends.find { it.id==chat.members.first() }; val last=lastMessages[chat.id]
            SheetCard(onClick={nav("chat:${chat.id}")}) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                    Avatar(if(chat.isGroup) "🌼" else friend?.emoji ?: "🌱",if(chat.isGroup) "" else friend?.avatar.orEmpty())
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                        Row { Text(chat.title,Modifier.weight(1f),fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis); Text(timeLabel(last?.created?:chat.created),fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(if(model.generatingChat==chat.id) "正在输入…" else last?.content?.ifBlank { if(last.image.isNotBlank()) "[图片]" else "回复未完成" } ?: "发一句问候吧",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)
                    }
                    var menu by remember { mutableStateOf(false) }
                    Box { TextButton(onClick={menu=true},contentPadding=PaddingValues(0.dp),modifier=Modifier.width(26.dp)){Text("⋯")}; DropdownMenu(menu,{menu=false}){DropdownMenuItem(text={Text("删除会话")},onClick={menu=false;deleting=chat})} }
                }
            }
        }
        if(sorted.isNotEmpty()&&visible.isEmpty()) item { EmptyState("🔎","没有找到相关聊天","换个词再试试") }
        item { Text("每一次认真倾听，都是一点靠近。",Modifier.fillMaxWidth().padding(vertical=18.dp),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    deleting?.let { c -> AlertDialog(onDismissRequest={deleting=null},title={Text("删除这段会话？")},text={Text("「${c.title}」的这段聊天记录将被移除，好友和记忆会保留。")},confirmButton={TextButton(onClick={model.deleteChat(c.id);deleting=null}){Text("删除")}},dismissButton={TextButton(onClick={deleting=null}){Text("取消")}}) }
}

@Composable fun FriendsScreen(model: LumiModel,state: AppData,nav:(String)->Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    val friends=state.friends.filter { search.isBlank() || it.name.contains(search,true) || it.style.contains(search,true) }.sortedWith(compareByDescending<Friend>{it.pinned}.thenBy{it.created})
    val import=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(model::importCard) }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(horizontal=22.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item { PageHeading("你的好友","每个角色，都有自己的故事。",action={IconButton(onClick={nav("edit:new")}){Glyph("plus",label="添加好友")}}) }
        item { Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) { Button(onClick={nav("edit:new")},Modifier.weight(1f),shape=RoundedCornerShape(15.dp)){Text("＋ 添加好友")}; OutlinedButton(onClick={import.launch(arrayOf("application/json","text/plain","application/octet-stream"))},Modifier.weight(1f),shape=RoundedCornerShape(15.dp)){Text("导入好友卡")} } }
        item { OutlinedTextField(search,{search=it},Modifier.fillMaxWidth().testTag("friends.search"),placeholder={Text("搜索好友名字或说话风格",fontSize=13.sp)},singleLine=true,shape=RoundedCornerShape(18.dp)) }
        item { SectionLabel("好友列表 · ${friends.size} 位") }
        items(friends,key={it.id}) { f ->
            SheetCard(modifier=Modifier.animateItem(),onClick={nav("friend:${f.id}")}) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(15.dp)) {
                    Avatar(f.emoji,f.avatar,62.dp)
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) {
                        Row(verticalAlignment=Alignment.CenterVertically) { Text(f.name,Modifier.weight(1f,fill=false),fontWeight=FontWeight.SemiBold,fontSize=17.sp,maxLines=1,overflow=TextOverflow.Ellipsis); if(f.pinned) Text("  ·  置顶",fontSize=10.sp,color=MaterialTheme.colorScheme.primary) }
                        Text(f.style.ifBlank { f.persona },maxLines=2,overflow=TextOverflow.Ellipsis,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${f.stage}  ·  相识 ${java.time.temporal.ChronoUnit.DAYS.between(java.time.Instant.ofEpochMilli(f.created).atZone(java.time.ZoneId.systemDefault()).toLocalDate(),LocalDate.now()).coerceAtLeast(0)+1} 天",fontSize=10.sp,color=MaterialTheme.colorScheme.primary)
                    }; Glyph("arrow")
                }
            }
        }
        if(state.friends.isEmpty()) item { EmptyState("🌱","新朋友在等你","可以自己创作，也可以导入 Lumi JSON 好友卡") }
        else if(friends.isEmpty()) item { EmptyState("🔎","没有找到这位好友","试试名字或说话风格中的关键词") }
        item { SheetCard { Eyebrow("创造一个独特的 TA"); Spacer(Modifier.height(8.dp)); Text("性格、背景和说话方式，\n都由你慢慢描绘。",fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,lineHeight=24.sp) } }
    }
}

@Composable fun MeScreen(model:LumiModel,state:AppData,nav:(String)->Unit) {
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(horizontal=22.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(15.dp)) {
        item { PageHeading("我的小天地","把喜欢的生活，慢慢收进来。") }
        item { SheetCard(onClick={nav("profile")}) { Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(16.dp)) {
            Avatar("☀️",state.profile.avatar,68.dp); Column(Modifier.weight(1f)) { Text(state.profile.displayName,fontSize=22.sp,fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(6.dp)); Text(state.profile.zodiac.ifBlank { "完善你的个人资料" },fontSize=12.sp,color=MaterialTheme.colorScheme.primary); Text(state.profile.bio,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2,overflow=TextOverflow.Ellipsis) }; Glyph("arrow")
        } } }
        item { Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            listOf(state.friends.size to "好友",state.messages.count { it.role=="user" } to "次倾诉",state.memories.size to "条记忆").forEach { (number,label) ->
                Surface(Modifier.weight(1f),shape=RoundedCornerShape(20.dp),color=MaterialTheme.colorScheme.surface) { Column(Modifier.padding(vertical=20.dp),horizontalAlignment=Alignment.CenterHorizontally) { Text(number.toString(),fontSize=24.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.primary); Spacer(Modifier.height(5.dp)); Text(label,fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) } }
            }
        } }
        item { SheetCard {
            MenuRow("settings","API 配置","${state.provider.name} · ${state.provider.model}"){nav("api")}
            MenuRow("memory","用量统计","查看模型调用和服务商返回的 Token 数"){nav("usage")}
            MenuRow("memory","备份与恢复","导出本机资料，或迁移 iOS 核心记录"){nav("backup")}
        } }
        item { SheetCard {
            Text("使用偏好",fontWeight=FontWeight.SemiBold); Spacer(Modifier.height(8.dp))
            Text("外观",fontSize=13.sp); Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) { listOf("system" to "跟随系统","light" to "浅色","dark" to "深色").forEach { (key,label) -> FilterChip(state.preferences.theme==key,{model.savePreferences(state.preferences.copy(theme=key))},label={Text(label,fontSize=11.sp)}) } }
            Row(verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("自动整理记忆",fontSize=14.sp); Text("每 8 次发送后调用模型，可能消耗额度",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Switch(state.preferences.autoMemory,{model.savePreferences(state.preferences.copy(autoMemory=it))}) }
            Row(verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text("自动朗读回复",fontSize=14.sp); Text("使用手机系统的文字转语音服务",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Switch(state.preferences.autoRead,{model.savePreferences(state.preferences.copy(autoRead=it))}) }
        } }
        item { SheetCard { MenuRow("heart","关于 Lumi","Android 移植版 · ${BuildConfig.VERSION_NAME.removeSuffix("-android")}"){nav("about")} } }
        item { Text("LUMI  ·  总有一些话，值得被记住。",Modifier.padding(vertical=14.dp),fontSize=10.sp,letterSpacing=1.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}
