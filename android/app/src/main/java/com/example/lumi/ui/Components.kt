package com.example.lumi.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.example.lumi.R
import com.example.lumi.data.ImageCache
import kotlinx.coroutines.CancellationException
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

val Green = Color(0xFF286452)
val Sage = Color(0xFFE8EFE6)
val Gold = Color(0xFFE9CE8E)
val Ink = Color(0xFF233D34)
val Muted = Color(0xFF79867C)

@Composable fun LumiTheme(theme: String, moments: Boolean = false, content: @Composable () -> Unit) {
    val dark = theme == "dark" || (theme == "system" && isSystemInDarkTheme())
    val colors = if (dark) darkColorScheme(primary = Color(0xFFA2CEB5), onPrimary = Color(0xFF113C2D),
        primaryContainer = Color(0xFF244436), onPrimaryContainer = Color(0xFFD6EADC),
        background = Color(0xFF131C18), surface = Color(0xFF1C2822), surfaceVariant = Color(0xFF27352C),
        onSurface = Color(0xFFE5ECE4), onSurfaceVariant = Color(0xFFB5C3B6), outline = Color(0xFF526457))
    else lightColorScheme(primary = Green, onPrimary = Color.White, primaryContainer = Sage, onPrimaryContainer = Ink,
        secondary = Color(0xFF8B784F), secondaryContainer = Color(0xFFF4EACF), background = Color(0xFFF7F8F2),
        surface = Color.White, surfaceVariant = Color(0xFFEEF2E9), onSurface = Ink, onSurfaceVariant = Color(0xFF6D7C71), outline = Color(0xFFDCE4D9))
    val palette = if (moments) colors.copy(
        primary = if (dark) Color(0xFF91A8C7) else Color(0xFF576B95),
        primaryContainer = if (dark) Color(0xFF303945) else Color(0xFFE8EDF5),
        onPrimaryContainer = if (dark) Color(0xFFCAD8EC) else Color(0xFF3D5278),
        secondaryContainer = if (dark) Color(0xFF303945) else Color(0xFFE8EDF5),
        onSecondaryContainer = if (dark) Color(0xFFCAD8EC) else Color(0xFF3D5278),
        background = if (dark) Color(0xFF191919) else Color.White,
        surface = if (dark) Color(0xFF191919) else Color.White,
        surfaceVariant = if (dark) Color(0xFF242424) else Color(0xFFF3F3F3),
        onSurface = if (dark) Color(0xFFE8E8E8) else Color(0xFF222222),
        onSurfaceVariant = if (dark) Color(0xFF8B8B8B) else Color(0xFF909090),
        outline = if (dark) Color(0xFF383838) else Color(0xFFE4E4E4)
    ) else colors
    MaterialTheme(colorScheme = palette, typography = Typography(
        headlineLarge = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-1).sp),
        titleLarge = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        bodyLarge = MaterialTheme.typography.bodyLarge.copy(lineHeight = 26.sp),
        bodyMedium = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp)), content = content)
}

@Composable fun Glyph(name: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurface, label: String? = null) {
    Canvas(modifier.size(23.dp).then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier)) {
        val w = size.width; val h = size.height; val stroke = Stroke(w * .065f)
        fun line(x: Float, y: Float, xx: Float, yy: Float) = drawLine(color, Offset(w*x,h*y), Offset(w*xx,h*yy), stroke.width, androidx.compose.ui.graphics.StrokeCap.Round)
        fun circle(x: Float, y: Float, r: Float) = drawCircle(color, w*r, Offset(w*x,h*y), style = stroke)
        when (name) {
            "chat" -> { drawRoundRect(color, Offset(w*.12f,h*.15f), Size(w*.76f,h*.59f), CornerRadius(w*.15f), style = stroke); line(.27f,.75f,.27f,.9f); line(.27f,.9f,.46f,.75f); line(.32f,.38f,.68f,.38f); line(.32f,.54f,.53f,.54f) }
            "friends" -> { circle(.4f,.31f,.17f); circle(.76f,.38f,.11f); drawArc(color,180f,180f,false,Offset(w*.11f,h*.57f),Size(w*.6f,h*.5f),style=stroke); drawArc(color,220f,130f,false,Offset(w*.58f,h*.64f),Size(w*.38f,h*.33f),style=stroke) }
            "moments" -> { circle(.5f,.5f,.36f); line(.5f,.14f,.5f,.4f); line(.83f,.36f,.61f,.47f); line(.75f,.77f,.57f,.59f); line(.25f,.77f,.43f,.59f); line(.17f,.36f,.39f,.47f) }
            "me" -> { circle(.5f,.31f,.18f); drawArc(color,180f,180f,false,Offset(w*.18f,h*.57f),Size(w*.64f,h*.55f),style=stroke) }
            "back" -> { line(.62f,.22f,.34f,.5f); line(.34f,.5f,.62f,.78f) }
            "arrow" -> { line(.4f,.27f,.63f,.5f); line(.63f,.5f,.4f,.73f) }
            "plus" -> { line(.5f,.2f,.5f,.8f); line(.2f,.5f,.8f,.5f) }
            "send" -> { line(.18f,.78f,.5f,.2f); line(.5f,.2f,.82f,.78f); line(.18f,.78f,.5f,.66f); line(.5f,.66f,.82f,.78f); line(.5f,.66f,.5f,.42f) }
            "photo" -> { drawRoundRect(color,Offset(w*.13f,h*.16f),Size(w*.74f,h*.68f),CornerRadius(w*.09f),style=stroke); circle(.66f,.34f,.065f); line(.19f,.71f,.4f,.48f); line(.4f,.48f,.72f,.81f) }
            "camera" -> { drawRoundRect(color,Offset(w*.1f,h*.3f),Size(w*.8f,h*.51f),CornerRadius(w*.08f),style=stroke); circle(.5f,.55f,.17f); line(.27f,.3f,.34f,.17f); line(.34f,.17f,.65f,.17f); line(.65f,.17f,.73f,.3f) }
            "mic" -> { drawRoundRect(color,Offset(w*.36f,h*.1f),Size(w*.28f,h*.51f),CornerRadius(w*.14f),style=stroke); drawArc(color,0f,180f,false,Offset(w*.23f,h*.3f),Size(w*.54f,h*.44f),style=stroke); line(.5f,.75f,.5f,.91f); line(.35f,.91f,.65f,.91f) }
            "memory" -> { drawRoundRect(color,Offset(w*.2f,h*.13f),Size(w*.6f,h*.74f),CornerRadius(w*.1f),style=stroke); line(.36f,.33f,.64f,.33f); line(.36f,.5f,.64f,.5f); line(.36f,.67f,.54f,.67f) }
            "settings" -> { circle(.5f,.5f,.15f); circle(.5f,.5f,.34f); repeat(6) { val a=it*Math.PI/3; line((.5+Math.cos(a)*.35).toFloat(),(.5+Math.sin(a)*.35).toFloat(),(.5+Math.cos(a)*.45).toFloat(),(.5+Math.sin(a)*.45).toFloat()) } }
            "heart" -> { val p=Path().apply { moveTo(w*.5f,h*.83f); cubicTo(w*-.15f,h*.4f,w*.25f,h*-.05f,w*.5f,h*.28f); cubicTo(w*.75f,h*-.05f,w*1.15f,h*.4f,w*.5f,h*.83f) }; drawPath(p,color,style=stroke) }
            else -> { line(.25f,.5f,.75f,.5f); line(.5f,.25f,.5f,.75f) }
        }
    }
}

@Composable fun Star(modifier: Modifier = Modifier, color: Color = Gold) {
    Canvas(modifier) { val w=size.width; val h=size.height
        drawPath(Path().apply { moveTo(w*.5f,0f); quadraticTo(w*.6f,h*.4f,w,h*.5f); quadraticTo(w*.6f,h*.6f,w*.5f,h); quadraticTo(w*.4f,h*.6f,0f,h*.5f); quadraticTo(w*.4f,h*.4f,w*.5f,0f) },color)
    }
}

@Composable fun LumiLogo(size: Dp = 72.dp) {
    Image(painterResource(R.drawable.lumi_logo), "Lumi 图标", Modifier.size(size).clip(RoundedCornerShape(size * .24f)), contentScale = ContentScale.Crop)
}

@Composable fun Base64Image(data: String, modifier: Modifier = Modifier, description: String = "图片", scale: ContentScale = ContentScale.Crop) {
    var image by remember(data) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(data) {
        try { image = ImageCache.load(data)?.asImageBitmap() }
        catch(e: CancellationException) { throw e }
        catch(_: Exception) { image = null }
    }
    val loaded = image
    if (loaded != null) Image(loaded,description,modifier,contentScale=scale)
    else Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant).semantics { contentDescription=description },contentAlignment=Alignment.Center) { Glyph("photo") }
}

@Composable fun ImagePreview(data: String, close: () -> Unit) {
    Dialog(onDismissRequest=close,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
            var zoom by remember { mutableFloatStateOf(1f) }
            var offset by remember { mutableStateOf(Offset.Zero) }
            val density = LocalDensity.current
            val width = with(density) { maxWidth.toPx() }
            val height = with(density) { maxHeight.toPx() }
            val transform = rememberTransformableState { change, pan, _ ->
                zoom = (zoom * change).coerceIn(1f,4f)
                val proposed = offset + pan
                offset = Offset(proposed.x.coerceIn(-width*(zoom-1)/2,width*(zoom-1)/2),proposed.y.coerceIn(-height*(zoom-1)/2,height*(zoom-1)/2))
            }
            Base64Image(data,Modifier.fillMaxSize().graphicsLayer { scaleX=zoom;scaleY=zoom;translationX=offset.x;translationY=offset.y }
                .transformable(transform).pointerInput(Unit) { detectTapGestures(onDoubleTap={ zoom=if(zoom>1f)1f else 2f;offset=Offset.Zero }) },"图片大图",ContentScale.Fit)
            TextButton(onClick=close,modifier=Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(12.dp)) { Text("关闭",color=Color.White) }
            Text("双指缩放 · 双击放大或还原",Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(20.dp),color=Color.White.copy(alpha=.7f),fontSize=12.sp)
        }
    }
}
@Composable fun Avatar(emoji: String = "🌱", image: String = "", size: Dp = 54.dp, onClick: (() -> Unit)? = null) {
    val m=Modifier.size(size).clip(RoundedCornerShape(size*.34f)).background(MaterialTheme.colorScheme.primaryContainer).then(if(onClick!=null) Modifier.clickable(onClick=onClick) else Modifier)
    if(image.isNotBlank()) Base64Image(image,m,"头像")
    else Box(m,contentAlignment=Alignment.Center) { Text(emoji,fontSize=(size.value*.49f).sp) }
}
@Composable fun SheetCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier.fillMaxWidth().then(if(onClick!=null) Modifier.clickable(onClick=onClick) else Modifier),shape=RoundedCornerShape(22.dp),color=MaterialTheme.colorScheme.surface) { Column(Modifier.padding(18.dp),content=content) }
}
@Composable fun Eyebrow(text: String) { Text(text,fontSize=11.sp,letterSpacing=2.sp,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.primary) }
@Composable fun SectionLabel(text: String, action: String? = null, onClick: () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
        Text(text,Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)
        if(action!=null) TextButton(onClick=onClick) { Text(action,fontSize=12.sp) }
    }
}
@Composable fun PageHeading(title: String, subtitle: String, action: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(top=20.dp,bottom=20.dp),verticalAlignment=Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Eyebrow("L U M I  /  陪伴日常"); Spacer(Modifier.height(9.dp)); Text(title,style=MaterialTheme.typography.headlineLarge); Spacer(Modifier.height(6.dp)); Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        action?.invoke()
    }
}
@Composable fun EmptyState(emoji: String, title: String, detail: String, action: String? = null, onClick: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=30.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Avatar(emoji,size=66.dp); Text(title,fontWeight=FontWeight.SemiBold); Text(detail,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodySmall)
        if(action!=null) FilledTonalButton(onClick=onClick) { Text(action) }
    }
}
@Composable fun FormField(value: String, onValue: (String) -> Unit, label: String, hint: String = "", lines: Int = 1, modifier: Modifier = Modifier) {
    OutlinedTextField(value,onValue,modifier.fillMaxWidth(),label={Text(label)},placeholder={if(hint.isNotBlank()) Text(hint)},minLines=lines,maxLines=if(lines==1) 1 else 8,singleLine=lines==1,shape=RoundedCornerShape(16.dp))
}
@Composable fun MenuRow(icon: String, title: String, subtitle: String = "", trailing: @Composable (() -> Unit)? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick=onClick).padding(vertical=13.dp,horizontal=3.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(MaterialTheme.colorScheme.primaryContainer),contentAlignment=Alignment.Center) { Glyph(icon,color=MaterialTheme.colorScheme.primary) }
        Column(Modifier.weight(1f)) { Text(title,fontWeight=FontWeight.Medium); if(subtitle.isNotBlank()) Text(subtitle,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2,overflow=TextOverflow.Ellipsis) }
        if(trailing!=null) trailing() else Glyph("arrow",color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable fun BackBar(title: String, onBack: () -> Unit, action: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min=62.dp).padding(horizontal=10.dp),verticalAlignment=Alignment.CenterVertically) {
        IconButton(onClick=onBack) { Glyph("back",label="返回") }; Text(title,Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold); action?.invoke()
    }
}
fun timeLabel(time: Long): String = SimpleDateFormat(if(java.time.Instant.ofEpochMilli(time).atZone(java.time.ZoneId.systemDefault()).toLocalDate()==java.time.LocalDate.now()) "HH:mm" else "MM月dd日",Locale.getDefault()).format(Date(time))
