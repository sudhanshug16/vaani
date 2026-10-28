package dev.vaani.keyboard

import org.junit.Assert.*
import org.junit.Test

class AudioLevelTest {
    private fun pcm(vararg values: Int) = values.flatMap { listOf(it.toByte(), (it shr 8).toByte()) }.toByteArray()
    @Test fun signedLittleEndianSamplesHaveSymmetricLevels() {
        for (value in listOf(64, 256, 4096, 16384, 32767)) {
            val positive = pcm(value, value)
            val negative = pcm(-value, -value)
            assertEquals(AudioLevel.pcm16(positive, positive.size), AudioLevel.pcm16(negative, negative.size))
        }
        assertEquals(100, AudioLevel.pcm16(pcm(-32768), 2))
        assertEquals(80, AudioLevel.pcm16(pcm(8192), 2))
    }
    @Test fun silenceAndUnusedBufferBytesDoNotInventSignal() {
        assertEquals(0, AudioLevel.pcm16(byteArrayOf(), 0))
        assertEquals(0, AudioLevel.pcm16(pcm(0, 0, 32767), 4))
        assertEquals(0, AudioLevel.pcm16(byteArrayOf(127), 1))
        assertThrows(IllegalArgumentException::class.java) { AudioLevel.pcm16(pcm(0), 3) }
    }
    @Test fun meterIncreasesWithSignalAndUsesRMSRatherThanPeak() {
        val amplitudes = listOf(0, 1, 32, 256, 1024, 4096, 16384, 32767)
        val levels = amplitudes.map { AudioLevel.pcm16(pcm(it), 2) }
        assertEquals(levels.sorted(), levels)
        assertTrue(levels.all { it in 0..100 })
        assertTrue(AudioLevel.pcm16(pcm(32767, 0, 0, 0), 8) < AudioLevel.pcm16(pcm(32767, 32767, 32767, 32767), 8))
    }
}
