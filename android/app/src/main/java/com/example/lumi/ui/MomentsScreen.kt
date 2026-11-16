package com.example.lumi.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.lumi.LumiModel
import com.example.lumi.R
import com.example.lumi.data.*

@Composable fun MomentsScreen(model: LumiModel, state: AppData, openFriend: (String) -> Unit, onBack: () -> Unit, friendId: String? = null) {
    val friend = state.friends.find { it.id == friendId }
    val posts = state.moments.filter { friendId == null || it.authorId == friendId }.sortedByDescending { it.created }
    var composing by rememberSaveable(friendId) { mutableStateOf(false) }
    var draft by rememberSaveable { mutableStateOf("") }
    var image by remember { mutableStateOf("") }
    var options by remember { mutableStateOf(false) }
    var browseFriends by remember { mutableStateOf(false) }
    var generateFriend by remember { mutableStateOf(false) }
    var replyPost by remember { mutableStateOf<String?>(null) }
    var commentPost by remember { mutableStateOf<String?>(null) }
    var comment by rememberSaveable { mutableStateOf("") }
    var deleting by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf<String?>(null) }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { model.loadImage(it) { loaded -> image = loaded } } }
    val cover = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { model.loadImage(it) { loaded -> model.saveMomentsCover(loaded, friendId) } } }
    LazyColumn(Modifier.fillMaxSize().testTag("moments.feed"), contentPadding = PaddingValues(bottom = 24.dp)) {
        item(key = "cover") {
            MomentsHeader(state, friend, onBack, { composing = true }, { options = true }, { cover.launch("image/*") })
            Spacer(Modifier.height(26.dp))
        }
        items(posts, key = { it.id }) { post ->
            MomentFeedRow(post, state, showsProfileLink = friendId == null, openFriend = openFriend,
                like = { model.likeMoment(post.id) }, writeComment = { comment = ""; commentPost = post.id },
                invite = { replyPost = post.id }, remove = { deleting = post.id }, openImage = { preview = post.image })
        }
        if (posts.isEmpty()) item {
            Column(Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Glyph("moments", Modifier.size(32.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Text(if (friend == null) "把今天留在这里" else "还没有动态", fontSize = 16.sp)
                Spacer(Modifier.height(8.dp))
                Text(if (friend == null) "点右上角相机，发照片或写下一点日常。" else "${friend.name}的生活片段会出现在这里。", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                if (friend != null) TextButton(onClick = { generateFriend = true }, enabled = model.busy.isBlank()) { Text("看看 TA 的近况") }
            }
        }
    }
    if (options) AlertDialog(onDismissRequest = { options = false }, title = { Text(if (friend == null) "朋友圈设置" else "${friend.name}的朋友圈") }, text = { Column {
        TextButton(onClick = { options = false; cover.launch("image/*") }) { Text(if (friend == null) "更换我的封面" else "更换 TA 的封面") }
        val customCover = friend?.momentsCover ?: state.profile.cover
        if (customCover.isNotBlank()) TextButton(onClick = { model.saveMomentsCover("", friendId); options = false }) { Text("恢复默认封面") }
        if (friend == null) TextButton(onClick = { options = false; browseFriends = true }) { Text("好友朋友圈") }
        TextButton(onClick = { options = false; generateFriend = true }, enabled = state.friends.isNotEmpty() && model.busy.isBlank()) { Text(if (friend == null) "看看好友近况" else "生成 TA 的动态") }
    } }, confirmButton = { TextButton(onClick = { options = false }) { Text("完成") } })
    if (browseFriends) AlertDialog(onDismissRequest = { browseFriends = false }, title = { Text("好友朋友圈") }, text = { Column {
        state.friends.forEach { f -> Row(Modifier.fillMaxWidth().clickable { browseFriends = false; openFriend(f.id) }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            MomentAvatar(f.emoji, f.avatar, 40.dp); Text(f.name, Modifier.weight(1f).padding(horizontal = 12.dp)); Glyph("arrow")
        } }
        if (state.friends.isEmpty()) Text("添加好友后，就能来看看 TA 的生活。")
    } }, confirmButton = { TextButton(onClick = { browseFriends = false }) { Text("关闭") } })
    if (composing) AlertDialog(onDismissRequest = { composing = false }, title = { Text("发表动态") }, text = { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        FormField(draft, { draft = it }, "这一刻的想法…", lines = 4)
        if (image.isNotBlank()) Base64Image(image, Modifier.fillMaxWidth().height(150.dp).clip(RoundedCornerShape(6.dp)), "动态图片", ContentScale.Fit)
        TextButton(onClick = { photo.launch("image/*") }) { Text(if (image.isBlank()) "＋ 添加图片" else "更换图片") }
        if (image.isNotBlank()) TextButton(onClick = { image = "" }) { Text("移除图片") }
    } }, confirmButton = { TextButton(onClick = { if (draft.isNotBlank() || image.isNotBlank()) { model.postMoment(draft, image); draft = ""; image = ""; composing = false } }, enabled = draft.isNotBlank() || image.isNotBlank()) { Text("发布") } }, dismissButton = { TextButton(onClick = { composing = false }) { Text("取消") } })
    if (generateFriend || replyPost != null) AlertDialog(onDismissRequest = { generateFriend = false; replyPost = null }, title = { Text(if (replyPost == null) "想看看谁的近况？" else "邀请谁来评论？") }, text = { Column {
        val candidates = if (friend != null && replyPost == null) listOf(friend) else state.friends
        candidates.forEach { f -> TextButton(onClick = {
            if (replyPost == null) model.generateMoment(f.id) else model.friendComment(replyPost!!, f.id)
            generateFriend = false; replyPost = null
        }) { Text("${f.emoji}  ${f.name}") } }
        Text("生成动态和评论会使用你配置的模型额度。", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    } }, confirmButton = { TextButton(onClick = { generateFriend = false; replyPost = null }) { Text("取消") } })
    commentPost?.let { id -> AlertDialog(onDismissRequest = { commentPost = null }, title = { Text("评论") }, text = { FormField(comment, { comment = it }, "写评论…", lines = 3) }, confirmButton = { TextButton(onClick = { if (comment.isNotBlank()) { model.commentMoment(id, comment); comment = ""; commentPost = null } }) { Text("发送") } }, dismissButton = { TextButton(onClick = { commentPost = null }) { Text("取消") } }) }
    deleting?.let { id -> AlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除这条动态？") }, text = { Text("动态与其评论会从本机移除。") }, confirmButton = { TextButton(onClick = { model.deleteMoment(id); deleting = null }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
    preview?.let { picture -> ImagePreview(picture) { preview = null } }
}

@Composable private fun MomentsHeader(state: AppData, friend: Friend?, back: () -> Unit, compose: () -> Unit, options: () -> Unit, changeCover: () -> Unit) {
    val customCover = friend?.momentsCover ?: state.profile.cover
    val daughterCover = friend != null && friend.name.trim() == "大肥鱼" && customCover.isBlank()
    val coverTag = when { friend == null -> "moments.cover.personal"; customCover.isNotBlank() -> "moments.cover.friend.${friend.id}"; daughterCover -> "moments.cover.daughter"; else -> "moments.cover.friend.default" }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val coverHeight = (maxWidth * .9f).coerceIn(260.dp, 380.dp)
        Box(Modifier.fillMaxWidth().height(coverHeight + 28.dp)) {
        Box(Modifier.fillMaxWidth().height(coverHeight).clickable(onClick = changeCover).testTag(coverTag)) {
            when {
                customCover.isNotBlank() -> Base64Image(customCover, Modifier.fillMaxSize(), if (friend == null) "我的朋友圈封面" else "${friend.name}的朋友圈背景")
                daughterCover -> Image(painterResource(R.drawable.daughter_moments_cover), "大肥鱼的朋友圈背景", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else -> {
                    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF253934), Color(0xFF516359), Color(0xFF2B3E37)))))
                    if (friend == null) Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Glyph("photo", color = Color.White.copy(alpha = .7f)); Text("轻触设置封面", color = Color.White.copy(alpha = .7f), fontSize = 12.sp)
                    }
                }
            }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = .38f), Color.Transparent, Color.Black.copy(alpha = .38f)))))
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 6.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = back) { Glyph("back", color = Color.White, label = "返回") }
                Text(friend?.let { "${it.name}的朋友圈" }.orEmpty(), Modifier.weight(1f), color = Color.White, fontSize = 14.sp, textAlign = TextAlign.Center)
                IconButton(onClick = options) { Glyph("settings", color = Color.White, label = "朋友圈设置") }
                if (friend == null) IconButton(onClick = compose) { Glyph("camera", color = Color.White, label = "发布动态") }
            }
        }
        Row(Modifier.align(Alignment.BottomEnd).fillMaxWidth().padding(horizontal = 22.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.Top) {
            Text(friend?.name ?: state.profile.displayName, Modifier.weight(1f).padding(top = 12.dp, end = 14.dp), color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End, style = LocalTextStyle.current.copy(shadow = Shadow(Color.Black, blurRadius = 6f)))
            MomentAvatar(friend?.emoji ?: "☀️", friend?.avatar ?: state.profile.avatar, 68.dp)
        }
        }
    }
}

@Composable private fun MomentAvatar(emoji: String, image: String, size: Dp, modifier: Modifier = Modifier, click: (() -> Unit)? = null) {
    val base = modifier.size(size).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceVariant).then(if (click != null) Modifier.clickable(onClick = click) else Modifier)
    if (image.isNotBlank()) Base64Image(image, base, "头像") else Box(base, contentAlignment = Alignment.Center) { Text(emoji, fontSize = (size.value * .5f).sp) }
}

@Composable private fun MomentFeedRow(post: Moment, state: AppData, showsProfileLink: Boolean, openFriend: (String) -> Unit, like: () -> Unit, writeComment: () -> Unit, invite: () -> Unit, remove: () -> Unit, openImage: () -> Unit) {
    val friend = state.friends.find { it.id == post.authorId }
    val name = if (post.authorId.isBlank()) state.profile.displayName else friend?.name ?: post.authorName
    val image = if (post.authorId.isBlank()) state.profile.avatar else friend?.avatar.orEmpty()
    val openProfile: (() -> Unit)? = if (friend != null && showsProfileLink) ({ openFriend(friend.id) }) else null
    val accent = MaterialTheme.colorScheme.primary
    var menu by remember(post.id) { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().testTag("moments.post.${post.id}").padding(horizontal = 22.dp, vertical = 16.dp), verticalAlignment = Alignment.Top) {
        MomentAvatar(friend?.emoji ?: "☀️", image, 40.dp, click = openProfile)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(name, Modifier.then(if (openProfile != null) Modifier.clickable(onClick = openProfile).testTag("moments.open.${post.authorId}") else Modifier), color = accent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            if (post.content.isNotBlank()) Text(post.content, fontSize = 15.sp, lineHeight = 23.sp)
            if (post.image.isNotBlank()) MomentPhoto(post.image, openImage)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(momentTime(post.created), Modifier.weight(1f), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Box {
                    Box(Modifier.size(width = 34.dp, height = 30.dp).clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.surfaceVariant).clickable { menu = true }.testTag("moments.actions.${post.id}").semantics { contentDescription = "动态操作" }, contentAlignment = Alignment.Center) {
                        Text("••", color = accent, letterSpacing = 2.sp)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text(if (post.liked) "取消点赞" else "赞") }, onClick = { menu = false; like() })
                        DropdownMenuItem(text = { Text("评论") }, onClick = { menu = false; writeComment() })
                        DropdownMenuItem(text = { Text("邀请好友评论") }, onClick = { menu = false; invite() }, enabled = state.friends.isNotEmpty())
                        DropdownMenuItem(text = { Text("删除动态") }, onClick = { menu = false; remove() })
                    }
                }
            }
            if (post.liked || post.comments.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                if (post.liked) {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Glyph("heart", Modifier.size(14.dp), color = accent); Text(state.profile.displayName, color = accent, fontSize = 12.sp)
                    }
                    if (post.comments.isNotEmpty()) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = .35f))
                }
                post.comments.forEach { c -> Text(buildAnnotatedString { withStyle(SpanStyle(color = accent, fontWeight = FontWeight.Medium)) { append(c.name); append("：") }; append(c.text) }, Modifier.padding(horizontal = 10.dp, vertical = 6.dp), fontSize = 12.sp, lineHeight = 19.sp) }
            }
        }
    }
    HorizontalDivider(Modifier.padding(start = 74.dp, end = 22.dp), color = MaterialTheme.colorScheme.outline.copy(alpha = .35f), thickness = .5.dp)
}

@Composable private fun MomentPhoto(image: String, open: () -> Unit) {
    val ratio = remember(image) { runCatching {
        val bytes = Base64.decode(image, Base64.DEFAULT); val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds); (bounds.outWidth.toFloat() / bounds.outHeight).coerceIn(.5f, 2f)
    }.getOrDefault(1f) }
    val width = when { ratio < .8f -> 126.dp; ratio > 1.3f -> 220.dp; else -> 170.dp }
    Base64Image(image, Modifier.width(width).aspectRatio(ratio).clip(RoundedCornerShape(2.dp)).clickable(onClick = open), "动态图片")
}

private fun momentTime(created: Long): String {
    val elapsed = ((System.currentTimeMillis() - created) / 60_000).coerceAtLeast(0)
    return when { elapsed < 1 -> "刚刚"; elapsed < 60 -> "${elapsed}分钟前"; elapsed < 24 * 60 -> "${elapsed / 60}小时前"; else -> timeLabel(created) }
}
