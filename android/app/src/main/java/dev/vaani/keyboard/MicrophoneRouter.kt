package dev.vaani.keyboard

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import org.json.JSONObject
import java.util.UUID

data class MicrophoneSnapshot(val inputs: List<MicrophoneOption>, val fingerprint: String,
    val decision: MicrophoneDecision, val profileName: String, val manualProfileID: String?)

/** Device-local preferences; never included in a shared export. */
class MicrophoneRouter(context: Context) {
    private val manager = context.getSystemService(AudioManager::class.java)
    private val preferences = context.getSharedPreferences("vaani.microphones", Context.MODE_PRIVATE)
    private fun inputDevices(): List<AudioDeviceInfo> {
        val types = mutableSetOf(AudioDeviceInfo.TYPE_BUILTIN_MIC, AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_LINE_ANALOG)
        if (Build.VERSION.SDK_INT >= 31) types.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
        return manager.getDevices(AudioManager.GET_DEVICES_INPUTS).filter { it.type in types }
    }
    fun resolve(uid: String): AudioDeviceInfo {
        val matches = inputDevices().filter { option(it).uid == uid }
        check(matches.size == 1) { "Preferred microphone is missing or cannot be uniquely identified. Choose another input." }
        return matches.single()
    }
    private fun option(device: AudioDeviceInfo): MicrophoneOption {
        val kind = when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
            else -> "Audio input"
        }
        val name = device.productName.toString()
        return MicrophoneOption(MicrophonePolicy.identity(device.type, name, device.address), "$name · $kind", device.id, device.type, device.address)
    }
    fun snapshot(): MicrophoneSnapshot {
        val devices = inputDevices()
        val inputs = MicrophonePolicy.displayLabels(devices.map(::option)).sortedBy { it.uid }
        val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map {
            MicrophonePolicy.identity(it.type, it.productName.toString(), it.address)
        }
        val fingerprint = MicrophonePolicy.fingerprint(inputs.map { it.uid }, outputs)
        val manualID = preferences.getString("activeProfile", null)
        val profile = profiles().firstOrNull { it.id == manualID }
        var preferred = if (manualID != null) profile?.microphoneUID ?: "" else preferences.getString("setup.$fingerprint", null)
        if (preferred == null && manualID == null) {
            // Migrate the first build's stable device choices, not its list index.
            val legacy = devices.sortedBy { legacyIdentity(it) }
            val legacyScenario = legacy.joinToString(";") { legacyIdentity(it).let { id -> "${id.length}:$id" } }
            val oldUID = preferences.getString(legacyScenario, null)
            if (oldUID != null) preferred = devices.firstOrNull { legacyIdentity(it) == oldUID }?.let { option(it).uid } ?: ""
        }
        return MicrophoneSnapshot(inputs, fingerprint, MicrophonePolicy.decide(inputs, preferred),
            if (manualID == null) "Automatic setup" else profile?.name ?: "Missing profile", manualID)
    }
    private fun legacyIdentity(device: AudioDeviceInfo) = "${device.type}|${device.productName}|${device.address}"
    private fun validateChoice(snapshot: MicrophoneSnapshot, uid: String) {
        val fresh = snapshot()
        require(fresh.fingerprint == snapshot.fingerprint && fresh.manualProfileID == snapshot.manualProfileID) { "Audio setup changed. Refresh microphones before saving." }
        require(fresh.inputs.count { it.uid == uid } == 1) { "This microphone cannot be uniquely identified. Disconnect the duplicate input." }
    }
    fun remember(snapshot: MicrophoneSnapshot, uid: String) {
        validateChoice(snapshot, uid)
        val editor = preferences.edit()
        if (snapshot.manualProfileID == null) editor.putString("setup.${snapshot.fingerprint}", uid)
        else {
            val profiles = profileJSON()
            val profile = profiles.getJSONObject(snapshot.manualProfileID)
            profile.put("microphoneUID", uid)
            editor.putString("profiles", profiles.toString())
        }
        check(editor.commit()) { "Could not save microphone choice." }
    }
    fun createProfile(name: String, snapshot: MicrophoneSnapshot, uid: String) {
        require(name.trim().isNotEmpty() && name.trim().length <= 80) { "Name the profile (up to 80 characters)." }
        validateChoice(snapshot, uid)
        val id = UUID.randomUUID().toString()
        val profiles = profileJSON().put(id, JSONObject().put("name", name.trim()).put("microphoneUID", uid))
        check(preferences.edit().putString("profiles", profiles.toString()).putString("activeProfile", id).commit()) { "Could not save profile." }
    }
    fun useProfile(id: String?) {
        require(id == null || profiles().any { it.id == id }) { "Profile no longer exists. Refresh microphones." }
        val editor = preferences.edit()
        if (id == null) editor.remove("activeProfile") else editor.putString("activeProfile", id)
        check(editor.commit()) { "Could not select profile." }
    }
    fun deleteProfile(id: String) {
        val profiles = profileJSON(); profiles.remove(id)
        val editor = preferences.edit().putString("profiles", profiles.toString())
        if (preferences.getString("activeProfile", null) == id) editor.remove("activeProfile")
        check(editor.commit()) { "Could not delete profile." }
    }
    private fun profileJSON() = JSONObject(preferences.getString("profiles", "{}")!!)
    fun profiles(): List<MicrophoneProfile> {
        val saved = profileJSON()
        return saved.keys().asSequence().map { id -> saved.getJSONObject(id).let {
            MicrophoneProfile(id, it.getString("name"), it.getString("microphoneUID"))
        } }.sortedBy { it.name.lowercase() }.toList()
    }
    companion object {
        fun isBluetooth(type: Int) = type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= 31 && type == AudioDeviceInfo.TYPE_BLE_HEADSET)
    }
}
