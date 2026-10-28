package dev.vaani.keyboard

import kotlin.math.log10
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Display-only RMS meter, -60 dBFS to full scale. Never retains audio samples. */
internal object AudioLevel {
    fun pcm16(bytes: ByteArray, count: Int): Int {
        require(count in 0..bytes.size)
        val samples = count / 2
        if (samples == 0) return 0
        var sum = 0.0
        for (index in 0 until samples) {
            val offset = index * 2
            val sample = ((bytes[offset].toInt() and 255) or (bytes[offset + 1].toInt() shl 8)).toShort().toDouble() / 32768.0
            sum += sample * sample
        }
        val rms = sqrt(sum / samples)
        return if (rms == 0.0) 0 else ((20 * log10(rms) + 60) * 100 / 60).roundToInt().coerceIn(0, 100)
    }
}
