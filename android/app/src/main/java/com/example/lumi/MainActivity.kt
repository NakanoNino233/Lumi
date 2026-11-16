package com.example.lumi

import android.content.Intent
import android.os.Bundle
import android.speech.tts.TextToSpeech
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModelProvider
import com.example.lumi.ui.LumiApp
import java.util.Locale

class MainActivity : ComponentActivity() {
    private lateinit var model: LumiModel
    private var speech: TextToSpeech? = null
    private var speechReady = false
    private var pendingSpeech: String? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        model = ViewModelProvider(this)[LumiModel::class.java]
        setContent { LumiApp(model, ::speak, ::share) }
    }
    private fun share(text: String) {
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "分享聊天记录"))
    }
    private fun speak(text: String) {
        if (speechReady) {
            speech?.language = if (text.any { it.code in 0x3400..0x9fff }) Locale.SIMPLIFIED_CHINESE else Locale.getDefault()
            val result = speech?.speak(text.take(3500), TextToSpeech.QUEUE_FLUSH, null, "lumi-${System.currentTimeMillis()}")
            if (result == TextToSpeech.ERROR) model.announce("系统朗读不可用，请检查手机的文字转语音设置")
            return
        }
        pendingSpeech = text
        if (speech == null) speech = TextToSpeech(this) { status ->
            runOnUiThread {
                speechReady = status == TextToSpeech.SUCCESS
                if (speechReady) pendingSpeech?.let { pendingSpeech = null; speak(it) }
                else model.announce("手机没有可用的朗读引擎，请在系统设置中安装或启用")
            }
        }
    }
    override fun onDestroy() { speech?.stop(); speech?.shutdown(); speech = null; super.onDestroy() }
}
