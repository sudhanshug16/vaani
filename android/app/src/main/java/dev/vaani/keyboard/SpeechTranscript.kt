package dev.vaani.keyboard

import org.json.JSONObject

/** A final replaces its partial; duplicate or reordered events never append twice. */
class SpeechTranscript {
    private val finals = sortedMapOf<Int, String>()
    private val partials = sortedMapOf<Int, String>()
    @Synchronized fun receive(event: JSONObject) {
        val type = event.getString("event")
        if (type != "transcript.partial" && type != "transcript.final") return
        val index = event.getInt("utterance_idx")
        require(index >= 0) { "Invalid utterance index" }
        val text = event.getString("text")
        if (type == "transcript.final") { finals[index] = text; partials.remove(index) }
        else if (!finals.containsKey(index)) partials[index] = text
    }
    @Synchronized fun text(finalOnly: Boolean = false): String =
        (if (finalOnly) finals else (partials + finals).toSortedMap()).values.joinToString(" ")
    @Synchronized fun hasPendingPartial(): Boolean = partials.values.any { it.isNotBlank() }
}
