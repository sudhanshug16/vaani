package dev.vaani.keyboard

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Open only for an explicit Bluetooth microphone. All requests are scoped to
 * the dictation lease and released before polishing or delivering a result. */
class BluetoothRoute private constructor(private val release: () -> Unit) : AutoCloseable {
    private var closed = false
    @Synchronized override fun close() { if (!closed) { closed = true; release() } }
    companion object {
        fun open(context: Context, input: MicrophoneOption, interrupted: () -> Boolean): BluetoothRoute {
            val manager = context.getSystemService(AudioManager::class.java)
            if (Build.VERSION.SDK_INT >= 31) {
                check(context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                    "Open Vaani and allow Bluetooth microphones first."
                }
                val candidates = manager.availableCommunicationDevices.filter { it.type == input.type }
                val addressed = candidates.filter { input.address.isNotEmpty() && it.address == input.address }
                val matching = if (addressed.isNotEmpty()) addressed else candidates.filter {
                    input.label.startsWith(it.productName.toString() + " ·")
                }
                check(matching.size == 1) { "Bluetooth headset has no unique communication route. Reconnect it and try again." }
                val target = matching.single()
                val lease = CommunicationRouteLease.acquire(object : CommunicationRoutePort {
                    override var mode: Int
                        get() = manager.mode
                        set(value) { manager.mode = value }
                    override fun request(deviceId: Int) = manager.setCommunicationDevice(target)
                    override fun clear() = manager.clearCommunicationDevice()
                }, target.id, AudioManager.MODE_NORMAL, AudioManager.MODE_IN_COMMUNICATION)
                try {
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(6)
                    while (manager.communicationDevice?.id != target.id) {
                        check(!interrupted()) { "Dictation stopped while connecting Bluetooth." }
                        check(System.nanoTime() < deadline) { "Bluetooth communication route timed out." }
                        Thread.sleep(40)
                    }
                    check(!interrupted()) { "Dictation stopped while connecting Bluetooth." }
                    return BluetoothRoute { lease.close() }
                } catch (error: Exception) { lease.close(); throw error }
            }
            return openLegacy(context, manager, interrupted)
        }
        @Suppress("DEPRECATION") // Android 9–11 have no communication-device API.
        private fun openLegacy(context: Context, manager: AudioManager, interrupted: () -> Boolean): BluetoothRoute {
            check(manager.mode == AudioManager.MODE_NORMAL) { "Another call is using communication audio." }
            check(manager.isBluetoothScoAvailableOffCall) { "This device does not support Bluetooth microphone recording outside calls." }
            val connected = CountDownLatch(1)
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1) == AudioManager.SCO_AUDIO_STATE_CONNECTED) connected.countDown()
                }
            }
            var registered = false; var requested = false; var ownsMode = false
            val cleanup = {
                try { if (registered) { registered = false; context.unregisterReceiver(receiver) } }
                finally {
                    try { if (requested) { requested = false; manager.stopBluetoothSco() } }
                    finally { if (ownsMode) { ownsMode = false; manager.mode = AudioManager.MODE_NORMAL } }
                }
            }
            try {
                val sticky = context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED))
                registered = true
                if (sticky?.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1) == AudioManager.SCO_AUDIO_STATE_CONNECTED) connected.countDown()
                ownsMode = true; manager.mode = AudioManager.MODE_IN_COMMUNICATION
                requested = true; manager.startBluetoothSco()
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(6)
                while (!connected.await(40, TimeUnit.MILLISECONDS)) {
                    check(!interrupted()) { "Dictation stopped while connecting Bluetooth." }
                    check(System.nanoTime() < deadline) { "Bluetooth SCO connection timed out." }
                }
                check(!interrupted()) { "Dictation stopped while connecting Bluetooth." }
                return BluetoothRoute(cleanup)
            } catch (error: Exception) { cleanup(); throw error }
        }
    }
}

/** Wrong/unknown startup frames are discarded while Android settles the route.
 * Once confirmed, any route change stops capture before those frames upload. */
class RecordingRouteVerifier(private val expectedId: Int, private val deadlineMillis: Long) {
    private var confirmed = false
    fun accept(actualId: Int?, nowMillis: Long): Boolean {
        if (actualId == expectedId) { confirmed = true; return true }
        check(!confirmed) { "Microphone route changed. Recording stopped; partial text preserved." }
        check(nowMillis < deadlineMillis) { "Android could not confirm the selected microphone. No unverified audio was sent." }
        return false
    }
}
