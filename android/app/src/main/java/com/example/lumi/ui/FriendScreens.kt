package com.example.lumi.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.lumi.LumiModel
import com.example.lumi.data.*

@Composable fun FriendEditorScreen(model:LumiModel,initial:Friend?,back:()->Unit) {
    val editorId=rememberSaveable(initial?.id){initial?.id ?: newId()}
    val original=remember(editorId){initial?:Friend(id=editorId)}
    var name by rememberSaveable(original.id){mutableStateOf(original.name)}
    var persona by rememberSaveable(original.id){mutableStateOf(original.persona)}
    var style by rememberSaveable(original.id){mutableStateOf(original.style)}
    var story by rememberSaveable(original.id){mutableStateOf(original.background)}
    var taboos by rememberSaveable(original.id){mutableStateOf(original.taboos)}
    var greeting by rememberSaveable(original.id){mutableStateOf(original.greeting)}
    var emoji by rememberSaveable(original.id){mutableStateOf(original.emoji)}
    var avatar by remember(original.id){mutableStateOf(original.avatar)}
    val photo=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()){it?.let { uri -> model.loadImage(uri){avatar=it} }}
    Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(22.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(18.dp)) { Avatar(emoji,avatar,76.dp){photo.launch("image/*")}; Column { Text("让 TA 有自己的样子",fontWeight=FontWeight.SemiBold); TextButton(onClick={photo.launch("image/*")}){Text("选择头像")}; if(avatar.isNotBlank()) TextButton(onClick={avatar=""}){Text("使用表情头像")} } }
        Row(horizontalArrangement=Arrangement.spacedBy(4.dp)) { listOf("🌱","🐋","🌸","🦊","🌙","🎧").forEach { e -> FilterChip(emoji==e,{emoji=e},label={Text(e)}) } }
        FormField(name,{name=it},"好友名字 *","最多 40 字")
        FormField(persona,{persona=it},"性格与人设 *","TA 是谁，喜欢什么，又怎样看待世界？",4)
        FormField(style,{style=it},"说话方式","简短自然、慢热幽默，或者别的风格",2)
        FormField(story,{story=it},"背景故事","给 TA 一段自己的生活",3)
        FormField(taboos,{taboos=it},"相处边界","哪些话题或表达需要避免？",2)
        FormField(greeting,{greeting=it},"开场白","新建聊天时的第一句话",2)
        Button(onClick={if(model.saveFriend(original.copy(name=name,persona=persona,style=style,background=story,taboos=taboos,greeting=greeting,emoji=emoji,avatar=avatar)))back()},Modifier.fillMaxWidth().height(52.dp)){Text("保存好友")}
        Text("角色设定仅用于虚构 AI 对话。资料保存在本机，请尊重真实人物和他人的边界。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable fun FriendScreen(model:LumiModel,state:AppData,friend:Friend,nav:(String)->Unit,back:()->Unit) {
    var delete by remember { mutableStateOf(false) }
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")){it?.let{uri->model.exportCard(uri,friend)}}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { Column(Modifier.fillMaxWidth().padding(vertical=12.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Avatar(friend.emoji,friend.avatar,92.dp); Text(friend.name,style=MaterialTheme.typography.headlineMedium,fontWeight=FontWeight.SemiBold)
            Text("${friend.stage}  ·  好感 ${friend.affection}",color=MaterialTheme.colorScheme.primary,fontSize=13.sp)
            LinearProgressIndicator(progress={friend.affection/100f},modifier=Modifier.fillMaxWidth(.5f),color=MaterialTheme.colorScheme.primary,trackColor=MaterialTheme.colorScheme.primaryContainer)
        } }
        item { Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) { Button(onClick={nav("chat:${model.startChat(friend)}")},Modifier.weight(1f)){Text("开始聊天")}; OutlinedButton(onClick={nav("edit:${friend.id}")},Modifier.weight(1f)){Text("编辑人设")} } }
        item { SheetCard { MenuRow("moments","朋友圈","看看 ${friend.name} 的生活片段"){nav("moments:${friend.id}")}; MenuRow("memory","共同记忆","${state.memories.count{it.friendId==friend.id}} 条本机记忆"){nav("memory:${friend.id}")}; MenuRow("memory","我们的日记","把聊天整理成一篇小记"){nav("diary:${friend.id}")}; MenuRow("heart","纪念日","记住值得庆祝的日子"){nav("anniversary:${friend.id}")} } }
        item { SheetCard { Eyebrow("关于 TA"); Spacer(Modifier.height(10.dp)); Text(friend.persona,fontSize=14.sp,lineHeight=24.sp); if(friend.background.isNotBlank()){Spacer(Modifier.height(14.dp));Text(friend.background,fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)} } }
        item { SheetCard { MenuRow("chat","开启新的会话","已有聊天会保留"){nav("chat:${model.startChat(friend,true)}")}; MenuRow("heart",if(friend.pinned)"取消置顶" else "置顶好友"){model.pinFriend(friend.id)}; MenuRow("friends","导出好友卡","兼容 Lumi schemaVersion 1 JSON"){export.launch("Lumi-${friend.name}.json")} } }
        item { TextButton(onClick={delete=true},Modifier.fillMaxWidth()){Text("删除好友",color=MaterialTheme.colorScheme.error)} }
    }
    if(delete) AlertDialog(onDismissRequest={delete=false},title={Text("删除 ${friend.name}？")},text={Text("相关聊天、包含该好友的群聊、记忆、日记、纪念日及其动态会被一起删除。建议先导出备份。")},confirmButton={TextButton(onClick={if(model.deleteFriend(friend.id)){delete=false;back()}}){Text("删除")}},dismissButton={TextButton(onClick={delete=false}){Text("取消")}})
}

@Composable fun MemoryScreen(model:LumiModel,state:AppData,friendId:String) {
    var add by rememberSaveable(friendId){mutableStateOf(false)}; var text by rememberSaveable(friendId){mutableStateOf("")}
    val memories=state.memories.filter{it.friendId==friendId}.sortedByDescending{it.pinned}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item{Eyebrow("被认真记住的小事");Text("${state.friends.find{it.id==friendId}?.name.orEmpty()} 的记忆",Modifier.padding(vertical=10.dp),style=MaterialTheme.typography.headlineSmall);Text("相关记忆会在聊天时被检索，置顶记忆优先保留。",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        item{Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onClick={add=true},Modifier.weight(1f)){Text("＋ 添加记忆")};OutlinedButton(onClick={model.extractMemories(friendId)},enabled=model.busy.isBlank(),modifier=Modifier.weight(1f)){Text("AI 整理")}}}
        item{Text("AI 整理会调用你配置的模型并消耗额度。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        items(memories,key={it.id}){memory->SheetCard{Row{Text(memory.category,Modifier.weight(1f),fontSize=11.sp,color=MaterialTheme.colorScheme.primary);if(memory.pinned)Text("已置顶",fontSize=11.sp,color=MaterialTheme.colorScheme.primary)};Spacer(Modifier.height(8.dp));Text(memory.text,fontSize=14.sp);Row{TextButton(onClick={model.pinMemory(memory.id)}){Text(if(memory.pinned)"取消置顶" else "置顶",fontSize=11.sp)};TextButton(onClick={model.removeMemory(memory.id)}){Text("移除",fontSize=11.sp)}}}}
        if(memories.isEmpty())item{EmptyState("🍃","记忆，从相处开始","先聊聊日常，或亲手记下一件小事。")}
    }
    if(add)AlertDialog(onDismissRequest={add=false},title={Text("添加一条记忆")},text={FormField(text,{text=it},"想让 TA 记住的事",lines=4)},confirmButton={TextButton(onClick={if(text.isNotBlank()){model.addMemory(friendId,text);text="";add=false}}){Text("保存")}},dismissButton={TextButton(onClick={add=false}){Text("取消")}})
}

@Composable fun DiaryScreen(model:LumiModel,state:AppData,friendId:String) {
    val diaries=state.diaries.filter{it.friendId==friendId}.sortedByDescending{it.day}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item{Eyebrow("把今天，留在这里");Spacer(Modifier.height(12.dp));Button(onClick={model.generateDiary(friendId)},enabled=model.busy.isBlank(),modifier=Modifier.fillMaxWidth()){Text("生成 / 更新今日小记")};Spacer(Modifier.height(8.dp));Text("只根据今天的真实对话整理，会调用模型并消耗额度。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        items(diaries,key={it.id}){d->SheetCard{Text(d.day,fontSize=12.sp,color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Medium);Spacer(Modifier.height(12.dp));Text(d.content,fontSize=14.sp,lineHeight=26.sp)}}
        if(diaries.isEmpty())item{EmptyState("📖","还没有小记","日常里的小小片段，也值得被留住。")}
    }
}

@Composable fun AnniversaryScreen(model:LumiModel,state:AppData,friendId:String) {
    var add by remember{mutableStateOf(false)};var title by remember{mutableStateOf("")};var day by remember{mutableStateOf(today())}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item{Button(onClick={add=true},Modifier.fillMaxWidth()){Text("＋ 添加纪念日")}}
        items(state.anniversaries.filter{it.friendId==friendId},key={it.id}){a->SheetCard{Text(a.title,fontSize=18.sp,fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(8.dp));Text(a.day,color=MaterialTheme.colorScheme.primary);val days=java.time.temporal.ChronoUnit.DAYS.between(java.time.LocalDate.parse(a.day),java.time.LocalDate.now());Text(if(days>=0)"已经一起走过 $days 天" else "还有 ${-days} 天",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);TextButton(onClick={model.removeAnniversary(a.id)}){Text("移除",fontSize=11.sp)}}}
        if(state.anniversaries.none{it.friendId==friendId})item{EmptyState("🗓️","总有一天，特别值得纪念","把初识、生日或约定写下来。")}
    }
    if(add)AlertDialog(onDismissRequest={add=false},title={Text("新的纪念日")},text={Column(verticalArrangement=Arrangement.spacedBy(12.dp)){FormField(title,{title=it},"标题");FormField(day,{day=it},"日期","YYYY-MM-DD")}},confirmButton={TextButton(onClick={if(model.addAnniversary(friendId,title,day)){title="";add=false}}){Text("保存")}},dismissButton={TextButton(onClick={add=false}){Text("取消")}})
}

@Composable fun GroupScreen(model:LumiModel,state:AppData,onCreated:(String)->Unit) {
    var title by rememberSaveable{mutableStateOf("")};var selected by rememberSaveable{mutableStateOf(listOf<String>())}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        item{FormField(title,{title=it},"群聊名称","例如：窗边的小茶会");Spacer(Modifier.height(12.dp));Text("选择 2–8 位好友。每次发送会依次请成员回复，产生多次模型调用。",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        items(state.friends,key={it.id}){f->SheetCard(onClick={selected=if(f.id in selected)selected-f.id else selected+f.id}){Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){Avatar(f.emoji,f.avatar,44.dp);Text(f.name,Modifier.weight(1f));Checkbox(f.id in selected,{checked->selected=if(checked)selected+f.id else selected-f.id})}}}
        item{Button(onClick={model.createGroup(title,selected.toList())?.let(onCreated)},enabled=selected.size in 2..8&&title.isNotBlank(),modifier=Modifier.fillMaxWidth()){Text("创建群聊")}}
    }
}
