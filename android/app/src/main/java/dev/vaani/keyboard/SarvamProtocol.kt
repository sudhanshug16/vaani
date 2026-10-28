package dev.vaani.keyboard

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject

internal object SarvamProtocol {
    fun url(settings: JSONObject, sampleRate: Int): HttpUrl {
        // Recognition hints are opt-in: names can replace unrelated quiet speech.
        val words = settings.getJSONArray("dictionary")
        val useHints = settings.optBoolean("recognitionHintsEnabled", false) && words.length() > 0
        val url = "https://api.sarvam.ai/speech-to-text-realtime/ws".toHttpUrl().newBuilder()
            .addQueryParameter("model", if (useHints) "saaras:v4" else settings.getString("sarvamModel"))
            .addQueryParameter("language_code", settings.getString("language"))
            .addQueryParameter("mode", settings.getString("mode"))
            .addQueryParameter("encoding", "linear16").addQueryParameter("sample_rate", sampleRate.toString())
            .addQueryParameter("stream_type", "balanced").addQueryParameter("endpointing", "vad")
        if (useHints) url.addQueryParameter("keyterms", words.toString())
        return url.build()
    }
}
