package com.example.lumi.ui

import android.content.Intent
import android.speech.RecognizerIntent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.lumi.LumiModel
import com.example.lumi.data.*
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

@Composable fun ChatScreen(model:LumiModel,state:AppData,chat:Chat,speak:(String)->Unit,nav:(String)->Unit) {
    var draft by rememberSaveable(chat.id) { mutableStateOf("") }
    var attachment by remember(chat.id) { mutableStateOf("") }
    var extras by rememberSaveable(chat.id) { mutableStateOf(false) }
    var preview by remember { mutableStateOf<String?>(null) }
    var followLatest by rememberSaveable(chat.id) { mutableStateOf(true) }
    val messages=state.messages.filter { it.chatId==chat.id }
    val friend=state.friends.find { it.id==chat.members.first() }
    val generating=model.generatingChat==chat.id
    val list=rememberLazyListState()
    val dragging by list.interactionSource.collectIsDraggedAsState()
    val scope=rememberCoroutineScope()
    val clipboard=LocalClipboardManager.current
    val photo=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { it?.let { uri -> model.loadImage(uri) {attachment=it} } }
    val voice=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let { draft=if(draft.isBlank()) it else "$draft $it" }
    }
    val lastCompleted=messages.lastOrNull { it.role=="assistant"&&it.status=="complete" }
    var lastRead by remember(chat.id) { mutableStateOf(lastCompleted?.id) }
    LaunchedEffect(lastCompleted?.id) {
        if(lastCompleted!=null&&lastCompleted.id!=lastRead) { lastRead=lastCompleted.id; if(state.preferences.autoRead) speak(lastCompleted.content) }
    }
    LaunchedEffect(dragging) { if(dragging) followLatest=false }
    LaunchedEffect(list) {
        snapshotFlow { list.layoutInfo.totalItemsCount>0 && !list.canScrollBackward }.distinctUntilChanged().collect { atLatest ->
            if(atLatest) followLatest=true
        }
    }
    LaunchedEffect(messages.size,messages.lastOrNull()?.content?.length,followLatest) {
        if(messages.isNotEmpty() && followLatest && !dragging) list.scrollToItem(0)
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        Surface(color=MaterialTheme.colorScheme.surface) { Row(Modifier.fillMaxWidth().padding(horizontal=22.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Avatar(if(chat.isGroup) "🌼" else friend?.emoji ?: "🌱",if(chat.isGroup) "" else friend?.avatar.orEmpty(),42.dp)
            Column(Modifier.weight(1f)) { Text(if(generating) "正在认真听你说…" else if(chat.isGroup) "${chat.members.size} 位 AI 好友的群聊" else "${friend?.stage ?: "初识"} · 每一句都有回音",fontSize=13.sp,fontWeight=FontWeight.Medium); Text("${state.provider.name} · ${state.provider.model}",fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
            IconButton(onClick={nav("memory:${chat.members.first()}")}){Glyph("memory",label="好友记忆")}
        } }
        if(messages.isEmpty()) Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.Center) { EmptyState(friend?.emoji ?: "🌼","今天，想从哪里聊起？","这里的聊天和记忆会保存在你的手机里。") }
        else Box(Modifier.weight(1f).fillMaxWidth()) {
        LazyColumn(Modifier.fillMaxSize().testTag("chat.messages"),state=list,reverseLayout=true,contentPadding=PaddingValues(horizontal=18.dp,vertical=20.dp),verticalArrangement=Arrangement.spacedBy(17.dp,Alignment.Bottom)) {
            items(messages.asReversed(),key={it.id}) { message ->
                val user=message.role=="user"; val sender=state.friends.find { it.id==message.senderId } ?: friend
                Column(Modifier.fillMaxWidth().testTag("chat.message.${message.id}"),horizontalAlignment=if(user) Alignment.End else Alignment.Start) {
                    Row(Modifier.fillMaxWidth(),horizontalArrangement=if(user) Arrangement.End else Arrangement.Start,verticalAlignment=Alignment.Top) {
                        if(!user) { Avatar(sender?.emoji?:"🌱",sender?.avatar.orEmpty(),30.dp); Spacer(Modifier.width(8.dp)) }
                        Column(Modifier.widthIn(max=300.dp).fillMaxWidth(if(user) .83f else .87f),horizontalAlignment=if(user) Alignment.End else Alignment.Start) {
                            if(!user&&chat.isGroup) Text(sender?.name ?: "好友",Modifier.padding(bottom=4.dp),fontSize=10.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            Surface(shape=RoundedCornerShape(topStart=if(user)20.dp else 5.dp,topEnd=if(user)5.dp else 20.dp,bottomEnd=20.dp,bottomStart=20.dp),
                                color=if(user) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface) {
                                Column(Modifier.padding(horizontal=15.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                                    if(message.image.isNotBlank()) Base64Image(message.image,Modifier.fillMaxWidth().heightIn(min=120.dp,max=260.dp).clickable{preview=message.image},"查看聊天图片",androidx.compose.ui.layout.ContentScale.Fit)
                                    if(message.content.isNotBlank()) SelectionContainer { Text(message.content,fontSize=15.sp,lineHeight=25.sp) }
                                    else if(message.status=="generating") Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) { CircularProgressIndicator(Modifier.size(13.dp),strokeWidth=1.5.dp); Text("想一想…",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                                    else if(message.status=="failed") Text("没有收到回复",fontSize=13.sp,color=MaterialTheme.colorScheme.error)
                                }
                            }
                            if(message.error.isNotBlank()) Text(message.error,Modifier.padding(top=6.dp),fontSize=11.sp,lineHeight=17.sp,color=MaterialTheme.colorScheme.error)
                            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                                Text(timeLabel(message.created),fontSize=9.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                if(message.content.isNotBlank()&&message.status!="generating") {
                                    TextButton(onClick={clipboard.setText(AnnotatedString(message.content));model.announce("已复制")},contentPadding=PaddingValues(horizontal=3.dp,vertical=0.dp),modifier=Modifier.height(32.dp)){Text("复制",fontSize=10.sp)}
                                    if(!user) TextButton(onClick={speak(message.content)},contentPadding=PaddingValues(horizontal=3.dp,vertical=0.dp),modifier=Modifier.height(32.dp)){Text("朗读",fontSize=10.sp)}
                                }
                            }
                        }
                    }
                }
            }
        }
        androidx.compose.animation.AnimatedVisibility(!followLatest && list.canScrollBackward,modifier=Modifier.align(Alignment.BottomEnd).padding(14.dp),enter=fadeIn(tween(150)),exit=fadeOut(tween(100))) {
            FilledTonalButton(onClick={scope.launch{list.animateScrollToItem(0);followLatest=true}},elevation=ButtonDefaults.filledTonalButtonElevation(defaultElevation=3.dp)) { Text("↓ 回到最新消息",fontSize=12.sp) }
        }
        }
        if(messages.any{it.role=="user"}&&!generating) Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.End) {
            TextButton(onClick={model.regenerate(chat.id)},enabled=model.generatingChat==null,contentPadding=PaddingValues(8.dp)){Text("↻ 重新生成",fontSize=11.sp)}
        }
        Surface(color=MaterialTheme.colorScheme.surface,shadowElevation=2.dp) {
            Column(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=10.dp)) {
                AnimatedVisibility(attachment.isNotBlank(),enter=expandVertically(tween(180))+fadeIn(),exit=shrinkVertically(tween(180))+fadeOut()) { Row(verticalAlignment=Alignment.CenterVertically) { Base64Image(attachment,Modifier.size(64.dp).padding(4.dp).clickable{preview=attachment},"待发送图片"); TextButton(onClick={attachment=""}){Text("移除图片")} } }
                AnimatedVisibility(extras,enter=expandVertically(tween(180))+fadeIn(),exit=shrinkVertically(tween(180))+fadeOut()) { Row(Modifier.fillMaxWidth().padding(bottom=6.dp),horizontalArrangement=Arrangement.SpaceEvenly,verticalAlignment=Alignment.CenterVertically) {
                    IconButton(onClick={photo.launch("image/*")}){Glyph("photo",label="添加图片")}
                    IconButton(onClick={try { voice.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply { putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM); putExtra(RecognizerIntent.EXTRA_PROMPT,"说给 Lumi 听") }) } catch(_:Exception) {model.announce("手机没有可用的语音识别服务")}}){Glyph("mic",label="语音输入")}
                    listOf("🌿","☀️","🥺","💚").forEach { emoji -> TextButton(onClick={draft+=emoji},contentPadding=PaddingValues(0.dp),modifier=Modifier.width(40.dp)){Text(emoji,fontSize=21.sp)} }
                } }
                Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(7.dp)) {
                    IconButton(onClick={extras=!extras},modifier=Modifier.padding(bottom=3.dp)){Glyph("plus",label="图片语音与表情")}
                    OutlinedTextField(draft,{draft=it},Modifier.weight(1f),placeholder={Text("说点什么…",fontSize=14.sp)},maxLines=5,shape=RoundedCornerShape(22.dp))
                    if(generating) FilledTonalIconButton(onClick=model::stopGeneration,modifier=Modifier.padding(bottom=4.dp).size(48.dp).semantics{contentDescription="停止生成"}){Text("■",fontSize=18.sp)}
                    else FilledIconButton(onClick={if(model.send(chat.id,draft,attachment)){draft="";attachment="";extras=false;followLatest=true}},enabled=(draft.isNotBlank()||attachment.isNotBlank())&&model.generatingChat==null,modifier=Modifier.padding(bottom=4.dp).size(48.dp)){Glyph("send",color=MaterialTheme.colorScheme.onPrimary,label="发送")}
                }
                Text("AI 角色可能出错，请以现实中的信息为准。",Modifier.align(Alignment.CenterHorizontally).padding(top=7.dp),fontSize=9.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    preview?.let { picture -> ImagePreview(picture) { preview=null } }
}
