package dev.vaani.keyboard

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

data class SyncSnapshot(val revision: String, val settings: JSONObject)

class SettingsSyncClient(private val pairing: SyncPairing) {
    fun fetch(): SyncSnapshot {
        val reply = exchange(SyncProtocol.request("get"))
        check(reply.getString("status") == "ok") { statusMessage(reply.getString("status")) }
        val revision = reply.getString("revision")
        check(revision.matches(Regex("[0-9a-f]{64}"))) { "Invalid settings revision" }
        return SyncSnapshot(revision, Preferences.canonical(reply.getJSONObject("settings")))
    }
    fun offer(snapshot: SyncSnapshot, settings: JSONObject): String {
        val reply = exchange(SyncProtocol.request("offer", snapshot.revision, settings))
        val status = reply.getString("status")
        check(status == "review") { statusMessage(status) }
        return "Sent to Mac. Open Vaani → Devices on the Mac to review and apply."
    }
    private fun exchange(request: JSONObject): JSONObject {
        pairing.validated()
        // Numeric address construction avoids DNS rebinding and local/LAN fallback.
        val address = InetAddress.getByAddress(pairing.host.split('.').map { it.toInt().toByte() }.toByteArray())
        val encrypted = SyncProtocol.seal(request.toString().toByteArray(Charsets.UTF_8), pairing.secret, "request")
        Socket().use { socket ->
            socket.soTimeout = 12000
            socket.connect(InetSocketAddress(address, pairing.port), 8000)
            val output = DataOutputStream(socket.getOutputStream())
            output.writeInt(encrypted.size); output.write(encrypted); output.flush()
            val input = DataInputStream(socket.getInputStream())
            val count = input.readInt()
            check(count in 28..SyncProtocol.maximumFrame) { "Invalid sync response size" }
            val frame = ByteArray(count); input.readFully(frame)
            val plain = try { SyncProtocol.open(frame, pairing.secret, "response") }
                catch (_: Exception) { error("Could not authenticate Mac. Pair again if the code was revoked.") }
            val reply = JSONObject(String(plain, Charsets.UTF_8))
            check(reply.getInt("version") == 1 && reply.getString("id") == request.getString("id")) { "Unexpected sync response" }
            return reply
        }
    }
    private fun statusMessage(status: String) = when (status) {
        "conflict" -> "Mac settings changed. Sync now again before sending."
        "dictating" -> "Mac is dictating. Finish dictation and try again."
        "pending" -> "The Mac already has settings waiting for review. Apply or discard them first."
        else -> "Mac could not complete sync."
    }
}
