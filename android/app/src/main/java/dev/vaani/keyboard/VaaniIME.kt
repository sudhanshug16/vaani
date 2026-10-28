package dev.vaani.keyboard

import android.graphics.Color
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.inputmethodservice.InputMethodService
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ProgressBar

class VaaniIME : InputMethodService() {
    private var session: DictationSession? = null
    private var generation = 0
    private val delivery = DictationDelivery()
    private var shifted = false
    private var symbols = false
    private var protectedField = false
    private lateinit var status: TextView
    private lateinit var levelMeter: ProgressBar
    private lateinit var dictate: Button
    private lateinit var insert: Button
    private lateinit var letters: LinearLayout
    private lateinit var microphonePanel: LinearLayout
    private lateinit var micButton: Button
    private lateinit var microphoneScroll: android.widget.ScrollView
    private lateinit var router: MicrophoneRouter
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) { refreshMicrophones() }
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) { refreshMicrophones() }
    }
    override fun onCreate() {
        super.onCreate(); router = MicrophoneRouter(this)
        getSystemService(AudioManager::class.java).registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
    }
    private val accent = Color.rgb(255, 156, 87)
    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(10), dp(8), dp(10), dp(8)); setBackgroundColor(Color.rgb(20, 21, 25))
        }
        status = TextView(this).apply { setTextColor(accent); textSize = 12f; visibility = View.GONE; accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE }
        root.addView(status)
        levelMeter = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100; progress = 0; visibility = View.GONE
            contentDescription = getString(R.string.microphone_level)
            progressTintList = android.content.res.ColorStateList.valueOf(accent)
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.rgb(52, 54, 62))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_NONE
        }
        root.addView(levelMeter, LinearLayout.LayoutParams(-1, dp(4)))
        micButton = button("Mic") {
            if (session == null) {
                microphoneScroll.visibility = if (microphoneScroll.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                refreshMicrophones()
            }
        }
        // Microphones stay behind a compact action, rather than a full summary row.
        microphonePanel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        microphoneScroll = android.widget.ScrollView(this).apply { addView(microphonePanel); visibility = View.GONE }
        root.addView(microphoneScroll, LinearLayout.LayoutParams(-1, dp(144)))
        val actions = LinearLayout(this)
        dictate = button("Dictate") { if (session == null) startDictation() else { session?.finish(); dictate.isEnabled = false; resetLevel(); showStatus(getString(R.string.finishing)) } }
        insert = button("Insert saved text") {
            val outcome = delivery.insert(protectedField) { currentInputConnection?.commitText(it, 1) == true }
            showStatus(if (outcome == DictationDelivery.Outcome.FAILED) getString(R.string.insert_failed) else null)
            insert.visibility = if (delivery.pending.isBlank()) View.GONE else View.VISIBLE
        }.apply { visibility = View.GONE }
        listOf(dictate, button("Cancel") { cancel() }, micButton,
            button("Next ⌁") { switchToNextInputMethod(false) }).forEach { actions.addView(it, LinearLayout.LayoutParams(0, dp(44), 1f)) }
        root.addView(actions)
        root.addView(insert, LinearLayout.LayoutParams(-1, dp(40)))
        letters = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(letters); renderLetters()
        dictate.isEnabled = !protectedField
        if (protectedField) showStatus(getString(R.string.password_voice_off))
        refreshMicrophones()
        return root
    }
    private fun startDictation() {
        if (protectedField) { showStatus(getString(R.string.password_voice_off)); return }
        val snapshot = try { router.snapshot() } catch (error: Exception) { showStatus(error.message); return }
        val selected = snapshot.decision as? MicrophoneDecision.Selected
        if (selected == null) {
            microphoneScroll.visibility = View.VISIBLE; refreshMicrophones()
            showStatus(when (snapshot.decision) {
                MicrophoneDecision.Unavailable -> getString(R.string.no_microphone)
                MicrophoneDecision.Missing -> getString(R.string.preferred_microphone_missing)
                MicrophoneDecision.AmbiguousIdentity -> getString(R.string.ambiguous_microphone)
                else -> getString(R.string.choose_microphone)
            })
            return
        }
        microphoneScroll.visibility = View.GONE; micButton.isEnabled = false
        delivery.clear(); insert.visibility = View.GONE; dictate.text = getString(R.string.finish); showStatus(getString(R.string.connecting))
        val token = ++generation
        val next = DictationSession(this, selected.microphone,
            onState = { text -> mainExecutor.execute { if (generation == token) {
                showStatus(if (text.startsWith("Listening")) null else text)
                if (text.startsWith("Listening")) levelMeter.visibility = View.VISIBLE else resetLevel()
            } } },
            onText = { _ -> },
            onResult = { text, error -> mainExecutor.execute {
                if (generation == token) {
                    val outcome = delivery.complete(text, error, protectedField) { currentInputConnection?.commitText(it, 1) == true }
                    showStatus(when (outcome) {
                        DictationDelivery.Outcome.INSERTED -> null
                        DictationDelivery.Outcome.EMPTY -> error ?: getString(R.string.no_speech_detected)
                        DictationDelivery.Outcome.REVIEW -> error
                        DictationDelivery.Outcome.FAILED -> getString(R.string.insert_failed)
                        DictationDelivery.Outcome.PROTECTED -> getString(R.string.password_voice_off)
                    })
                    resetLevel()
                    dictate.text = getString(R.string.dictate); dictate.isEnabled = !protectedField
                    insert.visibility = if (delivery.pending.isBlank()) View.GONE else View.VISIBLE
                    session = null; micButton.isEnabled = true; refreshMicrophones()
                }
            } }, onLevel = { level -> mainExecutor.execute { if (generation == token) levelMeter.progress = level } })
        session = next; next.start()
    }
    private fun cancel() {
        generation++; session?.cancel(); session = null; delivery.clear()
        if (::dictate.isInitialized) {
            resetLevel()
            dictate.text = getString(R.string.dictate); dictate.isEnabled = !protectedField; insert.visibility = View.GONE; micButton.isEnabled = true
            showStatus(if (protectedField) getString(R.string.password_voice_off) else null)
        }
    }
    private fun showStatus(message: String?) {
        status.text = message.orEmpty()
        status.visibility = if (message.isNullOrBlank()) View.GONE else View.VISIBLE
    }
    private fun resetLevel() {
        if (::levelMeter.isInitialized) { levelMeter.progress = 0; levelMeter.visibility = View.GONE }
    }
    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting); cancel()
        val type = attribute?.inputType ?: InputType.TYPE_NULL
        val variation = type and InputType.TYPE_MASK_VARIATION
        val category = type and InputType.TYPE_MASK_CLASS
        protectedField = type == InputType.TYPE_NULL ||
            (category == InputType.TYPE_CLASS_TEXT && variation in listOf(InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD, InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)) ||
            (category == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
        if (::dictate.isInitialized) { dictate.isEnabled = !protectedField; showStatus(if (protectedField) getString(R.string.password_voice_off) else null) }
    }
    override fun onFinishInput() { cancel(); super.onFinishInput() }
    override fun onWindowHidden() { cancel(); super.onWindowHidden() }
    override fun onDestroy() {
        cancel(); getSystemService(AudioManager::class.java).unregisterAudioDeviceCallback(deviceCallback); super.onDestroy()
    }
    override fun onWindowShown() { super.onWindowShown(); refreshMicrophones() }
    private fun refreshMicrophones() {
        if (!::microphonePanel.isInitialized || session != null) return
        try {
            val snapshot = router.snapshot()
            val selected = (snapshot.decision as? MicrophoneDecision.Selected)?.microphone
            micButton.contentDescription = getString(R.string.microphone_summary, snapshot.profileName, selected?.label ?: getString(R.string.choose_microphone))
            microphonePanel.removeAllViews()
            if (snapshot.inputs.isEmpty()) microphonePanel.addView(TextView(this).apply { setText(R.string.no_microphone); setTextColor(accent) })
            snapshot.inputs.forEach { mic ->
                microphonePanel.addView(button((if (selected?.uid == mic.uid) "✓ " else "") + mic.label) {
                    try {
                        router.remember(snapshot, mic.uid); microphoneScroll.visibility = View.GONE
                        showStatus(getString(R.string.microphone_saved)); refreshMicrophones()
                    } catch (error: Exception) { showStatus(error.message); refreshMicrophones() }
                })
            }
            microphonePanel.addView(button(getString(R.string.automatic_profile)) { selectProfile(null) })
            router.profiles().forEach { profile ->
                microphonePanel.addView(button(profile.name) { selectProfile(profile.id) })
            }
        } catch (error: Exception) { showStatus(error.message) }
    }
    private fun selectProfile(id: String?) {
        try { router.useProfile(id); refreshMicrophones() }
        catch (error: Exception) { showStatus(error.message) }
    }
    private fun renderLetters() {
        letters.removeAllViews()
        (if (symbols) listOf("1234567890", "@#₹%&*-+=", "()!?/:,\"") else listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")).forEach { row ->
            val line = LinearLayout(this)
            row.forEach { character ->
                val text = if (shifted) character.uppercase() else character.toString()
                line.addView(button(text) { currentInputConnection?.commitText(text, 1); if (shifted) { shifted = false; renderLetters() } }, LinearLayout.LayoutParams(0, dp(43), 1f))
            }
            letters.addView(line)
        }
        val bottom = LinearLayout(this)
        listOf(button(if (symbols) "ABC" else "123") { symbols = !symbols; renderLetters() },
            button("⇧") { shifted = !shifted; renderLetters() }, button(".") { currentInputConnection?.commitText(".", 1) },
            button("space") { currentInputConnection?.commitText(" ", 1) }, button("⌫") {
                if (currentInputConnection?.let(EditorActions::backspace) == false) showStatus(getString(R.string.delete_failed))
            }, button("↵") { if (!sendDefaultEditorAction(true)) currentInputConnection?.commitText("\n", 1) }).forEachIndexed { index, view ->
            bottom.addView(view, LinearLayout.LayoutParams(0, dp(43), if (index == 3) 3f else 1f))
        }
        letters.addView(bottom)
    }
    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label; isAllCaps = false; textSize = 13f; minWidth = 0; minimumWidth = 0
        backgroundTintList = android.content.res.ColorStateList(
            arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
            intArrayOf(Color.rgb(34, 35, 40), Color.rgb(52, 54, 62)))
        setTextColor(android.content.res.ColorStateList(
            arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
            intArrayOf(Color.rgb(120, 122, 130), Color.WHITE)))
        setPadding(0, 0, 0, 0); setOnClickListener { action() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
