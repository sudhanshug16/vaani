package dev.vaani.keyboard

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

internal object SarvamProtocol {
    fun url(settings: JSONObject, sampleRate: Int): HttpUrl {
        // Sarvam accepts recognition hints only on v4. Keep saved model choices
        // intact so clearing the dictionary restores the user's chosen model.
        val words = settings.getJSONArray("dictionary")
        val url = "https://api.sarvam.ai/speech-to-text-realtime/ws".toHttpUrl().newBuilder()
            .addQueryParameter("model", if (words.length() > 0) "saaras:v4" else settings.getString("sarvamModel"))
            .addQueryParameter("language_code", settings.getString("language"))
            .addQueryParameter("mode", settings.getString("mode"))
            .addQueryParameter("encoding", "linear16").addQueryParameter("sample_rate", sampleRate.toString())
            .addQueryParameter("stream_type", "balanced").addQueryParameter("endpointing", "vad")
        if (words.length() > 0) url.addQueryParameter("keyterms", words.toString())
        return url.build()
    }
}
