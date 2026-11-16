package com.example.lumi

import com.example.lumi.data.Memory
import com.example.lumi.data.MemoryRecall
import com.example.lumi.network.Endpoint
import com.example.lumi.network.SseDecoder
import com.example.lumi.network.visibleReply
import org.junit.Assert.*
import org.junit.Test

class ProtocolTest {
    @Test fun completionPathsPreserveGatewayPrefixes() {
        assertEquals("https://api.openai.com/v1/chat/completions", Endpoint.resolve(" https://api.openai.com/ "))
        assertEquals("https://example.org/custom/v2/chat/completions", Endpoint.resolve("https://example.org/custom/v2/"))
        assertEquals("https://example.org/v1/chat/completions", Endpoint.resolve("https://example.org/v1/chat/completions"))
        assertEquals("https://api.anthropic.com/v1/messages", Endpoint.resolve("https://api.anthropic.com", "anthropic"))
    }
    @Test fun credentialsAndInsecureDestinationsAreRejected() {
        listOf("http://example.org", "https://secret@example.org/v1", "https://example.org?key=test", "file:///tmp/mock", "https://example.org/#x").forEach {
            assertThrows(IllegalArgumentException::class.java) { Endpoint.resolve(it) }
        }
        assertThrows(IllegalArgumentException::class.java) { Endpoint.resolve("http://localhost:8888") }
        assertEquals("http://127.0.0.1:8888/chat/completions", Endpoint.resolve("http://127.0.0.1:8888",allowLocal=true))
    }
    @Test fun sseHandlesEveryChunkBoundaryAndCrLf() {
        val source=": heartbeat\r\nevent: text\r\ndata: 你好\r\ndata: 世界\r\n\r\ndata: [DONE]\n\n"
        for(boundary in 0..source.length){
            val events=mutableListOf<String>();val decoder=SseDecoder(events::add)
            decoder.append(source.substring(0,boundary));decoder.append(source.substring(boundary));decoder.finish()
            assertEquals(listOf("你好\n世界","[DONE]"),events)
        }
    }
    @Test fun sseFlushesFinalUnterminatedEventAndLimitsSize() {
        val events=mutableListOf<String>();val decoder=SseDecoder(events::add)
        decoder.append("data: final");decoder.finish();assertEquals(listOf("final"),events)
        assertThrows(IllegalArgumentException::class.java){SseDecoder{}.append("data: "+"x".repeat(1_048_577))}
    }
    @Test fun replyMetadataNeverLeaksIntoChat() {
        assertEquals("你好",visibleReply("你好\n<mem id=\"abc\"/><meta affection_delta=\"2\" mood=\"开心\"/>"))
        assertEquals("你好",visibleReply("你好<meta affection_delta=\""))
    }
    @Test fun memoryRecallUsesChinesePairsAndPinnedFacts() {
        val unrelated=Memory(friendId="f",text="喜欢下雨",importance=5)
        val related=Memory(friendId="f",text="周末想去书店",importance=3)
        val pinned=Memory(friendId="f",text="名字是小林",pinned=true)
        val recalled=MemoryRecall.recall("今天去书店吗",listOf(unrelated,related,pinned))
        assertTrue(related in recalled);assertTrue(pinned in recalled);assertFalse(unrelated in recalled)
        assertEquals(listOf(pinned),MemoryRecall.recall("",listOf(unrelated,pinned)))
    }
}
