package com.example.lumi.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.security.MessageDigest

/** Decode off the UI thread and reuse bounded previews across avatars and lists. */
object ImageCache {
    private val cache = object : LruCache<String, Bitmap>(20 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val decodeLock = Mutex()

    suspend fun load(data: String): Bitmap? = withContext(Dispatchers.IO) {
        require(data.length <= 7_000_000) { "图片过大" }
        val key = MessageDigest.getInstance("SHA-256").digest(data.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        decodeLock.withLock {
            cache.get(key)?.let { return@withLock it }
            val bytes = Base64.decode(data, Base64.DEFAULT)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            require(bounds.outWidth in 1..8192 && bounds.outHeight in 1..8192 && bounds.outWidth.toLong() * bounds.outHeight <= 20_000_000)
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1200) sample *= 2
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })?.also { cache.put(key, it) }
        }
    }
}
