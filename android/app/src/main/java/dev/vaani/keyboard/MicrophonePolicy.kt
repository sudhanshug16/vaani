package dev.vaani.keyboard

data class MicrophoneOption(val uid: String, val label: String, val deviceId: Int, val type: Int, val address: String)
data class MicrophoneProfile(val id: String, val name: String, val microphoneUID: String)
sealed class MicrophoneDecision {
    data class Selected(val microphone: MicrophoneOption) : MicrophoneDecision()
    data object Ask : MicrophoneDecision()
    data object Missing : MicrophoneDecision()
    data object Unavailable : MicrophoneDecision()
    data object AmbiguousIdentity : MicrophoneDecision()
}

object MicrophonePolicy {
    /** Presentation only: routing and saved setup identities never depend on labels. */
    fun displayLabels(inputs: List<MicrophoneOption>): List<MicrophoneOption> {
        val located = inputs.map { input ->
            // Android's built-in mic addresses describe physical locations on some phones.
            val location = if (input.type == 15 /* TYPE_BUILTIN_MIC */) when (input.address.lowercase(java.util.Locale.ROOT)) {
                "back" -> "Back"
                "bottom" -> "Bottom"
                "front" -> "Front"
                "top" -> "Top"
                else -> null
            } else null
            input.copy(label = input.label + (location?.let { " · $it" } ?: ""))
        }
        val groups = located.groupBy { it.label }
        return located.map { input ->
            val group = groups.getValue(input.label)
            if (group.size == 1) input else {
                val ids = group.map { it.uid }.distinct()
                if (group.count { it.uid == input.uid } > 1) input.copy(label = "${input.label} · Cannot distinguish")
                else {
                    val hashes = ids.associateWith { id ->
                        java.security.MessageDigest.getInstance("SHA-256").digest(id.toByteArray(Charsets.UTF_8))
                            .joinToString("") { "%02x".format(it) }
                    }
                    val hash = hashes.getValue(input.uid)
                    val length = (6..64).first { n -> hashes.values.count { it.take(n) == hash.take(n) } == 1 }
                    input.copy(label = "${input.label} · ${hash.take(length)}")
                }
            }
        }
    }
    fun identity(type: Int, name: String, address: String) = encode(listOf(type.toString(), name, address))
    fun fingerprint(inputs: List<String>, outputs: List<String>) = encode(listOf("inputs") + inputs.sorted() + listOf("outputs") + outputs.sorted())
    private fun encode(values: List<String>) = values.joinToString("|") { "${it.length}:$it" }
    fun decide(inputs: List<MicrophoneOption>, preferredUID: String?): MicrophoneDecision {
        if (inputs.isEmpty()) return MicrophoneDecision.Unavailable
        if (preferredUID != null) {
            val matching = inputs.filter { it.uid == preferredUID }
            return when (matching.size) {
                0 -> MicrophoneDecision.Missing
                1 -> MicrophoneDecision.Selected(matching.single())
                else -> MicrophoneDecision.AmbiguousIdentity
            }
        }
        return if (inputs.size == 1) MicrophoneDecision.Selected(inputs.single()) else MicrophoneDecision.Ask
    }
}

/** A communication request belongs to this app. Clearing it lets Android resume
 * its previous policy; re-requesting an observed prior device would create a new
 * persistent request that Vaani never owned in the first place. */
interface CommunicationRoutePort {
    var mode: Int
    fun request(deviceId: Int): Boolean
    fun clear()
}
class CommunicationRouteLease private constructor(private val port: CommunicationRoutePort,
    private val normalMode: Int, private var ownsMode: Boolean = false, private var ownsRequest: Boolean = false) : AutoCloseable {
    companion object {
        fun acquire(port: CommunicationRoutePort, deviceId: Int, normalMode: Int, communicationMode: Int): CommunicationRouteLease {
            check(port.mode == normalMode) { "Another call is using communication audio. Finish it before dictating with Bluetooth." }
            val lease = CommunicationRouteLease(port, normalMode)
            try {
                lease.ownsMode = true
                port.mode = communicationMode
                // Clear even a failed request: platform implementations may reject
                // after partially applying it. Requests are scoped to our client.
                lease.ownsRequest = true
                check(port.request(deviceId)) { "Android refused the Bluetooth communication route." }
                return lease
            } catch (error: Exception) { lease.close(); throw error }
        }
    }
    @Synchronized override fun close() {
        try {
            if (ownsRequest) { ownsRequest = false; port.clear() }
        } finally {
            if (ownsMode) { ownsMode = false; port.mode = normalMode }
        }
    }
}
