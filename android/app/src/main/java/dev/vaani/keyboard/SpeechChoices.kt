package dev.vaani.keyboard

/** Display names are separate from the protocol values stored and synced. */
internal object SpeechChoices {
    private val names = mapOf(
        "auto" to "Auto-detect · including Hinglish", "en-IN" to "English", "hi-IN" to "Hindi",
        "bn-IN" to "Bengali", "kn-IN" to "Kannada", "ml-IN" to "Malayalam", "mr-IN" to "Marathi",
        "or-IN" to "Odia", "pa-IN" to "Punjabi", "ta-IN" to "Tamil", "te-IN" to "Telugu",
        "gu-IN" to "Gujarati", "as-IN" to "Assamese", "ur-IN" to "Urdu", "ne-IN" to "Nepali",
        "kok-IN" to "Konkani", "ks-IN" to "Kashmiri", "sd-IN" to "Sindhi", "sa-IN" to "Sanskrit",
        "sat-IN" to "Santali", "mni-IN" to "Manipuri", "brx-IN" to "Bodo", "mai-IN" to "Maithili", "doi-IN" to "Dogri")
    private val outputs = mapOf(
        "translit" to "Romanized / Latin script", "transcribe" to "Original script",
        "codemix" to "Native + English", "translate" to "English translation", "verbatim" to "Verbatim")
    fun language(code: String) = names[code] ?: code
    fun output(code: String) = outputs[code] ?: code
}
