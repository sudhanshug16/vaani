package dev.vaani.keyboard

import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ColorDrawable
import android.inputmethodservice.InputMethodService
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/** A voice input surface. Ordinary typing stays with the user's other keyboard. */
class VaaniIME : InputMethodService() {
    private enum class Phase { READY, CONNECTING, LISTENING, FINISHING }
    private var phase = Phase.READY
    private var session: DictationSession? = null
    private var generation = 0
    private val delivery = DictationDelivery()
    private var protectedField = false
    private var needsMicrophone = false
    private lateinit var surface: LinearLayout
    private lateinit var headline: TextView
    private lateinit var voiceIcon: ImageView
    private lateinit var status: TextView
    private lateinit var levelMeter: ProgressBar
    private lateinit var cancelButton: Button
    private lateinit var insert: Button
    private lateinit var settings: ImageButton
    private lateinit var router: MicrophoneRouter
    private val accent = Color.rgb(255, 156, 87)
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) { refreshMicrophones() }
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) { refreshMicrophones() }
    }
    override fun onCreate() {
        super.onCreate()
        router = MicrophoneRouter(this)
        getSystemService(AudioManager::class.java).registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
    }
    override fun onEvaluateFullscreenMode() = false
    override fun onCreateInputView(): View {
        val surfaceColor = Color.rgb(20, 21, 25)
        surface = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            this.background = RippleDrawable(ColorStateList.valueOf(Color.rgb(52, 54, 62)), ColorDrawable(surfaceColor), null)
            isFocusable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setOnClickListener { toggle() }
            setOnApplyWindowInsetsListener { view, insets ->
                // System navigation/cutout only: IME insets describe this entire
                // keyboard and must never be added again as bottom padding.
                if (Build.VERSION.SDK_INT >= 30) {
                    val safe = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                    view.setPadding(dp(12) + safe.left, dp(8) + safe.top, dp(12) + safe.right, dp(8) + safe.bottom)
                } else {
                    view.setPadding(dp(12) + insets.systemWindowInsetLeft, dp(8), dp(12) + insets.systemWindowInsetRight, dp(8) + insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        val header = LinearLayout(this).apply { gravity = Gravity.END }
        settings = ImageButton(this).apply {
            setImageResource(R.drawable.ic_voice_settings)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            imageTintList = ColorStateList.valueOf(Color.rgb(176, 178, 188))
            contentDescription = getString(R.string.voice_settings)
            background = null
            setOnClickListener {
                cancel()
                requestHideSelf(0)
                startActivity(Intent(this@VaaniIME, SettingsActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("section", if (needsMicrophone) "Microphones" else "Voice"))
            }
        }
        header.addView(settings, LinearLayout.LayoutParams(dp(48), dp(48)))
        surface.addView(header, LinearLayout.LayoutParams(-1, dp(48)))
        val compact = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val center = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            minimumHeight = dp(if (compact) 100 else 148)
            setPadding(dp(20), dp(8), dp(20), dp(12))
        }
        voiceIcon = ImageView(this).apply {
            setImageResource(R.drawable.ic_voice_surface)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        center.addView(voiceIcon, LinearLayout.LayoutParams(dp(if (compact) 32 else 44), dp(if (compact) 32 else 44)))
        headline = TextView(this).apply {
            textSize = 20f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(4))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        center.addView(headline)
        status = TextView(this).apply {
            textSize = 13f; setTextColor(Color.rgb(176, 178, 188)); gravity = Gravity.CENTER
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        center.addView(status, LinearLayout.LayoutParams(-1, -2))
        levelMeter = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100; progress = 0; visibility = View.INVISIBLE
            contentDescription = getString(R.string.microphone_level)
            progressTintList = ColorStateList.valueOf(accent)
            progressBackgroundTintList = ColorStateList.valueOf(Color.rgb(52, 54, 62))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        center.addView(levelMeter, LinearLayout.LayoutParams(dp(96), dp(3)).apply { topMargin = dp(12) })
        surface.addView(center, LinearLayout.LayoutParams(-1, -2))
        val controls = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        controls.addView(button("⌨") {
            cancel()
            if (!switchToNextInputMethod(false)) getSystemService(InputMethodManager::class.java).showInputMethodPicker()
        }.apply { contentDescription = getString(R.string.switch_keyboard) }, LinearLayout.LayoutParams(dp(48), dp(48)))
        controls.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
        insert = button(getString(R.string.insert_saved_text)) {
            val outcome = delivery.insert(protectedField) { currentInputConnection?.commitText(it, 1) == true }
            showStatus(if (outcome == DictationDelivery.Outcome.FAILED) getString(R.string.insert_failed) else null)
            insert.visibility = if (delivery.pending.isBlank()) View.GONE else View.VISIBLE
        }.apply { visibility = View.GONE }
        controls.addView(insert, LinearLayout.LayoutParams(-2, dp(48)))
        cancelButton = button(getString(R.string.cancel_dictation)) { cancel() }.apply { visibility = View.GONE }
        controls.addView(cancelButton, LinearLayout.LayoutParams(-2, dp(48)))
        controls.addView(ImageButton(this).apply {
            setImageResource(R.drawable.ic_voice_backspace)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            imageTintList = ColorStateList.valueOf(accent)
            contentDescription = getString(R.string.backspace)
            background = null
            setOnClickListener {
                val connection = currentInputConnection
                if (connection == null || !EditorActions.backspace(connection)) {
                    showStatus(getString(R.string.delete_failed))
                }
            }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        surface.addView(controls, LinearLayout.LayoutParams(-1, dp(48)))
        render()
        refreshMicrophones()
        surface.requestApplyInsets()
        return surface
    }
    private fun toggle() {
        when (phase) {
            Phase.READY -> startDictation()
            Phase.LISTENING -> { phase = Phase.FINISHING; render(); session?.finish() }
            else -> Unit // Cancel remains usable during connection/polishing.
        }
    }
    private fun startDictation() {
        if (protectedField) { showStatus(getString(R.string.password_voice_off)); return }
        val snapshot = try { router.snapshot() } catch (error: Exception) { showStatus(error.message); return }
        val selected = snapshot.decision as? MicrophoneDecision.Selected
        needsMicrophone = selected == null
        if (selected == null) {
            showStatus(when (snapshot.decision) {
                MicrophoneDecision.Unavailable -> getString(R.string.no_microphone)
                MicrophoneDecision.Missing -> getString(R.string.preferred_microphone_missing)
                MicrophoneDecision.AmbiguousIdentity -> getString(R.string.ambiguous_microphone)
                else -> getString(R.string.choose_microphone_in_settings)
            })
            return
        }
        delivery.clear(); insert.visibility = View.GONE
        phase = Phase.CONNECTING; render()
        val token = ++generation
        val next = DictationSession(this, selected.microphone,
            onState = { text -> mainExecutor.execute { if (generation == token) {
                if (phase == Phase.FINISHING && !text.startsWith("Finishing") && !text.startsWith("Polishing")) return@execute
                if (phase != Phase.FINISHING) {
                    phase = if (text.startsWith("Listening")) Phase.LISTENING else if (text == getString(R.string.finishing) || text.startsWith("Polishing")) Phase.FINISHING else Phase.CONNECTING
                }
                render()
                if (phase != Phase.LISTENING) showStatus(text)
            } } }, onText = { _ -> },
            onResult = { text, error -> mainExecutor.execute {
                if (generation == token) {
                    val outcome = delivery.complete(text, error, protectedField) { currentInputConnection?.commitText(it, 1) == true }
                    session = null; phase = Phase.READY; render()
                    showStatus(when (outcome) {
                        DictationDelivery.Outcome.INSERTED -> null
                        DictationDelivery.Outcome.EMPTY -> error ?: getString(R.string.no_speech_detected)
                        DictationDelivery.Outcome.REVIEW -> error
                        DictationDelivery.Outcome.FAILED -> getString(R.string.insert_failed)
                        DictationDelivery.Outcome.PROTECTED -> getString(R.string.password_voice_off)
                    })
                    insert.visibility = if (delivery.pending.isBlank()) View.GONE else View.VISIBLE
                    refreshMicrophones()
                }
            } }, onLevel = { level -> mainExecutor.execute { if (generation == token) levelMeter.progress = level } })
        session = next; next.start()
    }
    private fun render() {
        if (!::surface.isInitialized) return
        val title = when {
            protectedField -> getString(R.string.voice_unavailable)
            phase == Phase.CONNECTING -> getString(R.string.connecting)
            phase == Phase.LISTENING -> getString(R.string.tap_to_finish)
            phase == Phase.FINISHING -> getString(R.string.finishing)
            else -> getString(R.string.tap_to_dictate)
        }
        voiceIcon.setImageResource(if (phase == Phase.LISTENING) R.drawable.ic_voice_stop else R.drawable.ic_voice_surface)
        voiceIcon.imageTintList = ColorStateList.valueOf(if (protectedField) Color.rgb(96, 98, 108) else accent)
        headline.text = title
        surface.contentDescription = title
        surface.isEnabled = !protectedField && phase in listOf(Phase.READY, Phase.LISTENING)
        cancelButton.visibility = if (phase != Phase.READY) View.VISIBLE else View.GONE
        settings.isEnabled = phase == Phase.READY
        levelMeter.visibility = if (phase == Phase.LISTENING) View.VISIBLE else View.INVISIBLE
        if (phase != Phase.LISTENING) levelMeter.progress = 0
        showStatus(if (protectedField) getString(R.string.password_voice_off) else null)
    }
    private fun cancel() {
        generation++; session?.cancel(); session = null; delivery.clear(); phase = Phase.READY
        if (::surface.isInitialized) { insert.visibility = View.GONE; render() }
    }
    private fun showStatus(message: String?) {
        status.text = message ?: when (phase) {
            Phase.READY -> getString(R.string.tap_anywhere_start)
            Phase.LISTENING -> getString(R.string.tap_anywhere_finish)
            else -> getString(R.string.cancel_available)
        }
        status.setTextColor(if (message.isNullOrBlank()) Color.rgb(176, 178, 188) else accent)
    }
    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting); cancel()
        val type = attribute?.inputType ?: InputType.TYPE_NULL
        val variation = type and InputType.TYPE_MASK_VARIATION
        val category = type and InputType.TYPE_MASK_CLASS
        protectedField = type == InputType.TYPE_NULL ||
            (category == InputType.TYPE_CLASS_TEXT && variation in listOf(InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD, InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)) ||
            (category == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
        render()
    }
    override fun onFinishInput() { cancel(); super.onFinishInput() }
    override fun onWindowHidden() { cancel(); super.onWindowHidden() }
    override fun onDestroy() {
        cancel(); getSystemService(AudioManager::class.java).unregisterAudioDeviceCallback(deviceCallback); super.onDestroy()
    }
    override fun onWindowShown() { super.onWindowShown(); refreshMicrophones() }
    private fun refreshMicrophones() {
        if (!::settings.isInitialized || session != null) return
        try {
            val snapshot = router.snapshot()
            val selected = (snapshot.decision as? MicrophoneDecision.Selected)?.microphone
            needsMicrophone = selected == null
            settings.contentDescription = getString(R.string.voice_settings) + " · " + getString(R.string.microphone_summary, snapshot.profileName, selected?.label ?: getString(R.string.choose_microphone))
        } catch (error: Exception) { showStatus(error.message) }
    }
    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label; isAllCaps = false; textSize = 14f; minWidth = dp(48); minimumWidth = dp(48)
        background = null; setTextColor(accent); setPadding(dp(12), 0, dp(12), 0)
        setOnClickListener { action() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
