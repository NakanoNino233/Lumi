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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.lumi.BuildConfig
import com.example.lumi.LumiModel
import com.example.lumi.data.*

@Composable fun ApiScreen(model:LumiModel,state:AppData) {
    var draft by remember { mutableStateOf(state.provider) }
    var key by remember { mutableStateOf(model.secretFor(state.provider.id)) }
    var showKey by remember{mutableStateOf(false)}
    Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(22.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Eyebrow("连接属于你的 AI 服务")
        Text("选择服务模板，填写自己的服务地址、模型名称和 API Key。",fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            listOf("DeepSeek","OpenAI","Claude","自定义").forEach { name->
                OutlinedButton(onClick={draft=when(name){
                    "DeepSeek"->draft.copy(name=name,baseUrl="https://api.deepseek.com",model="deepseek-flash",protocol="openai",vision=false)
                    "OpenAI"->draft.copy(name=name,baseUrl="https://api.openai.com/v1",model="gpt-4o-mini",protocol="openai",vision=true)
                    "Claude"->draft.copy(name=name,baseUrl="https://api.anthropic.com/v1",model="",protocol="anthropic",vision=true)
                    else->draft.copy(name="自定义",baseUrl="",model="",protocol="openai",vision=false)
                };key=""},modifier=Modifier.weight(1f),contentPadding=PaddingValues(horizontal=1.dp,vertical=10.dp)){Text(name,fontSize=10.sp,maxLines=1)}
            }
        }
        FormField(draft.name,{draft=draft.copy(name=it)},"配置名称")
        FormField(draft.baseUrl,{draft=draft.copy(baseUrl=it)},"服务地址","https://example.com/v1")
        FormField(draft.model,{draft=draft.copy(model=it)},"模型名称","以服务商控制台实际可用名称为准")
        OutlinedTextField(key,{key=it},Modifier.fillMaxWidth(),label={Text("API Key")},singleLine=true,shape=androidx.compose.foundation.shape.RoundedCornerShape(16.dp),visualTransformation=if(showKey)VisualTransformation.None else PasswordVisualTransformation(),trailingIcon={TextButton(onClick={showKey=!showKey}){Text(if(showKey)"隐藏" else "显示",fontSize=11.sp)}})
        Text("密钥通过 Android Keystore 加密，仅保存在本机。测试连接也会发送一次模型请求。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment=Alignment.CenterVertically){Text("接口协议",Modifier.weight(1f),fontSize=14.sp);FilterChip(draft.protocol=="openai",{draft=draft.copy(protocol="openai")},label={Text("OpenAI 兼容",fontSize=11.sp)});Spacer(Modifier.width(7.dp));FilterChip(draft.protocol=="anthropic",{draft=draft.copy(protocol="anthropic")},label={Text("Anthropic",fontSize=11.sp)})}
        Row(verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text("图片理解",fontSize=14.sp);Text("请确认所选模型实际支持图片",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)};Switch(draft.vision,{draft=draft.copy(vision=it)})}
        Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){
            OutlinedButton(onClick={model.testProvider(draft,key)},enabled=model.busy.isBlank(),modifier=Modifier.weight(1f)){Text("测试连接")}
            Button(onClick={model.saveProvider(draft,key)},enabled=model.busy.isBlank(),modifier=Modifier.weight(1f)){Text("保存并使用")}
        }
        OutlinedButton(onClick={draft=draft.copy(id=newId(),name="${draft.name}（新配置）");key=""},modifier=Modifier.fillMaxWidth()){Text("另存为新配置")}
        SectionLabel("已保存配置")
        state.providers.forEach { provider->SheetCard(onClick={draft=provider;key=model.secretFor(provider.id);showKey=false}){Row(verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(provider.name,fontWeight=FontWeight.SemiBold);Text(provider.model,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)};RadioButton(state.provider.id==provider.id,{model.activateProvider(provider.id);draft=provider;key=model.secretFor(provider.id);showKey=false})}}}
        Text("模板名称仅作填写示例，不提供 API 额度。服务地址会自动补全聊天接口路径；自定义网关请填写正确的接口前缀。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable fun ProfileScreen(model:LumiModel,initial:Profile,onSaved:()->Unit,welcome:Boolean=false) {
    var name by rememberSaveable{mutableStateOf(initial.name)};var birthday by rememberSaveable{mutableStateOf(initial.birthday)}
    var bio by rememberSaveable{mutableStateOf(initial.bio)};var avatar by remember{mutableStateOf(initial.avatar)};var cover by remember{mutableStateOf(initial.cover)};var tags by rememberSaveable{mutableStateOf(initial.tags)}
    val photo=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()){it?.let{uri->model.loadImage(uri){avatar=it}}}
    val coverPicker=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()){it?.let{uri->model.loadImage(uri){cover=it}}}
    Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(26.dp),verticalArrangement=Arrangement.spacedBy(17.dp)) {
        if(welcome){Spacer(Modifier.height(12.dp));LumiLogo(72.dp);Eyebrow("你好，欢迎来到 LUMI");Text("先从认识你开始。",style=MaterialTheme.typography.headlineLarge);Text("留下一张小小的资料卡，\n让每一句问候，都更像对你说。",fontSize=14.sp,lineHeight=25.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(18.dp)){Avatar("☀️",avatar,80.dp){photo.launch("image/*")};TextButton(onClick={photo.launch("image/*")}){Text("选择头像")}}
        FormField(name,{name=it},"你的名字","可以是昵称，最多 40 字")
        FormField(birthday,{birthday=it},"生日（可不填）","YYYY-MM-DD")
        FormField(bio,{bio=it},"个性签名",lines=2)
        if(!welcome){FormField(tags,{tags=it},"朋友圈标签","日常 · 陪伴 · 小确幸");OutlinedButton(onClick={coverPicker.launch("image/*")}){Text("选择朋友圈封面")};if(cover.isNotBlank()){Base64Image(cover,Modifier.fillMaxWidth().height(130.dp),"朋友圈封面");TextButton(onClick={cover=""}){Text("恢复默认封面")}}}
        Button(onClick={if(model.saveProfile(initial.copy(name=name,birthday=birthday.trim(),bio=bio,avatar=avatar,cover=cover,tags=tags)))onSaved()},modifier=Modifier.fillMaxWidth().height(52.dp)){Text(if(welcome)"开启我的 Lumi" else "保存资料")}
        if(welcome)TextButton(onClick={model.skipProfile();onSaved()},modifier=Modifier.align(Alignment.CenterHorizontally)){Text("先逛逛，稍后填写")}
        Text("资料保存在本机。聊天时，名称和生日等资料会作为上下文发送给你配置的模型服务。",fontSize=11.sp,lineHeight=20.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable fun BackupScreen(model:LumiModel,state:AppData) {
    val save=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")){it?.let(model::exportBackup)}
    val restore=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()){it?.let(model::previewBackup)}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(22.dp),verticalArrangement=Arrangement.spacedBy(18.dp)){
        Eyebrow("把故事，好好保存")
        SheetCard{Text("本机资料",fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(10.dp));Text("${state.friends.size} 位好友 · ${state.messages.size} 条消息\n${state.memories.size} 条记忆 · ${state.diaries.size} 篇日记\n${state.moments.size} 条动态",fontSize=14.sp,lineHeight=27.sp)}
        Button(onClick={save.launch("Lumi-Android-${today()}.zip")},enabled=model.busy.isBlank(),modifier=Modifier.fillMaxWidth().height(52.dp)){Text("导出完整 Android 备份")}
        OutlinedButton(onClick={restore.launch(arrayOf("application/zip","application/json","application/octet-stream"))},enabled=model.busy.isBlank(),modifier=Modifier.fillMaxWidth().height(52.dp)){Text("导入并预览备份")}
        Text("Android 备份包含好友、消息与图片、记忆、日记、纪念日、动态、资料和配置，不包含 API Key。\n\niOS v1 备份支持迁移好友、私聊文本、记忆、日记、纪念日、朋友圈文本和资料。群聊、附件、表情包、技能、小组件等 iOS 专属数据尚未迁移。\n\n导入会先校验数据并展示条目数量，确认后替换当前资料。更换设备或卸载应用前，请把备份另存到安全的位置。",fontSize=12.sp,lineHeight=23.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable fun UsageScreen(state:AppData){
    val input=state.usage.sumOf{it.input};val output=state.usage.sumOf{it.output}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
        item{Eyebrow("每一段对话，都有迹可循");Spacer(Modifier.height(14.dp));SheetCard{Text("${state.usage.size}",fontSize=36.sp,color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.SemiBold);Text("次成功请求",fontSize=12.sp);Spacer(Modifier.height(14.dp));Text("输入 ${"%,d".format(input)}  /  输出 ${"%,d".format(output)} Tokens",fontSize=14.sp);Spacer(Modifier.height(8.dp));Text("仅统计服务商实际返回的 Token。未返回用量的请求会显示 0，不代表免费；请以服务商账单为准。",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
        items(state.usage.asReversed().take(100),key={it.id}){u->SheetCard{Row{Text(u.kind,Modifier.weight(1f),fontWeight=FontWeight.SemiBold);Text(timeLabel(u.created),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)};Text(u.model,fontSize=12.sp,color=MaterialTheme.colorScheme.primary);Text("输入 ${u.input} · 输出 ${u.output}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
        if(state.usage.isEmpty())item{EmptyState("🍵","还没有调用记录","连接模型后，成功请求会记录在这里。")}
    }
}

@Composable fun AboutScreen(){
    val context=LocalContext.current
    val license=remember{context.assets.open("LICENSE").bufferedReader().use{it.readText()}}
    var showLicense by remember{mutableStateOf(false)}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(26.dp),verticalArrangement=Arrangement.spacedBy(18.dp)){
        LumiLogo(80.dp);Text("Lumi",fontSize=34.sp,fontWeight=FontWeight.SemiBold);Eyebrow("ANDROID  /  ${BuildConfig.VERSION_NAME.removeSuffix("-android")}")
        Text("和 AI 好友聊日常，也把彼此的故事留在这里。",fontSize=16.sp,lineHeight=28.sp)
        SheetCard{Text("原作与移植",fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(10.dp));Text("原项目：NakanoNino233 / Lumi\n上游版本：91a3174（2026-11-15 获取）\nhttps://github.com/NakanoNino233/Lumi\n\nAndroid 端使用 Kotlin 与 Jetpack Compose 重写，沿用原项目的角色卡、记忆检索思路及提示词。此为个人非商业移植版，并非原作者发布的官方 Android 版本。",fontSize=13.sp,lineHeight=23.sp)}
        SheetCard{Text("许可与素材",fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(10.dp));Text("Required Notice: Copyright (c) 2026 NakanoNino233 and Lumi contributors\n\n采用 PolyForm Noncommercial License 1.0.0，适用于个人学习、实验与非商业用途。应用保留完整许可和第三方声明。本机个人移植版保留原项目的图标、角色照片与默认封面。图片权利独立于代码许可；完整来源及权利说明随应用保留。内置几何表情素材采用上游 CC0 声明。",fontSize=12.sp,lineHeight=23.sp);TextButton(onClick={showLicense=!showLicense}){Text(if(showLicense)"收起完整许可" else "查看完整许可")};if(showLicense)Text(license,fontSize=10.sp,lineHeight=17.sp)}
        Text("隐私：内容仅在本机存储；进行聊天、连接测试、记忆整理、日记和 AI 动态时，相应内容会发送到你配置的服务商。没有内置模型额度或后台上传服务。\n\n当前版本未移植 iOS 小组件、实时活动、主动通知、天气工具、技能市场及自定义表情包库。",fontSize=12.sp,lineHeight=23.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
