package dev.vaani.keyboard

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.view.View
import android.os.Bundle
import android.os.Build
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.inputmethod.InputMethodManager
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject

class SettingsActivity : Activity() {
    private lateinit var prefs: Preferences
    private lateinit var root: LinearLayout
    private lateinit var message: TextView
    private lateinit var sectionScroll: ScrollView
    private lateinit var sectionContainer: LinearLayout
    private val sections = linkedMapOf<String, LinearLayout>()
    private val sectionButtons = linkedMapOf<String, Button>()
    private val sectionOffsets = mutableMapOf<String, Int>()
    private var currentSection = "Voice"
    private lateinit var sarvam: EditText
    private lateinit var apiKey: EditText
    private lateinit var endpoint: EditText
    private lateinit var model: EditText
    private lateinit var prompt: EditText
    private val dictionaryWords = mutableListOf<String>()
    private lateinit var recognitionHints: Switch
    private lateinit var dictionaryEntry: EditText
    private lateinit var dictionaryList: LinearLayout
    private lateinit var dictionaryCount: TextView
    private lateinit var dictionaryAdd: Button
    private lateinit var dictionaryCancel: Button
    private var dictionaryEditingIndex: Int? = null
    private lateinit var enabled: Switch
    private lateinit var language: Spinner
    private lateinit var mode: Spinner
    private lateinit var speechModel: Spinner
    private lateinit var serviceTier: Spinner
    private lateinit var reasoningEffort: Spinner
    private lateinit var microphone: Spinner
    private lateinit var router: MicrophoneRouter
    private lateinit var routeSnapshot: MicrophoneSnapshot
    private lateinit var profiles: Spinner
    private lateinit var profileName: EditText
    private lateinit var pairing: EditText
    private lateinit var syncStatus: TextView
    private var syncBusy = false
    private var profileIDs: List<String?> = emptyList()
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) { refreshRouting() }
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) { refreshRouting() }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); prefs = Preferences(this); router = MicrophoneRouter(this)
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
            setBackgroundColor(Color.rgb(20, 21, 25))
        }
        root = shell
        setContentView(shell)
        label("vaani", 30f); label("Speak naturally. Keep your language.")
        val tabs = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        shell.addView(tabs)
        for (names in listOf(listOf("Voice", "Microphones", "Polish"), listOf("Dictionary", "Devices"))) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            tabs.addView(row)
            for (name in names) {
                val tab = actionButton(name) { selectSection(name) }.apply { textSize = 12f; minWidth = 0; minimumWidth = 0 }
                row.addView(tab, LinearLayout.LayoutParams(0, dp(48), 1f))
                sectionButtons[name] = tab
            }
        }
        message = label("").apply { setTextColor(Color.rgb(255, 156, 87)) }
        sectionContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        sectionScroll = ScrollView(this).apply { addView(sectionContainer); isFillViewport = true }
        shell.addView(sectionScroll, LinearLayout.LayoutParams(-1, 0, 1f))
        section("Voice")
        button("1 · Allow microphone") { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 10) }
        if (Build.VERSION.SDK_INT >= 31) button("Allow Bluetooth microphones (optional)") {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 11)
        }
        button("2 · Enable Vaani keyboard") { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
        button("3 · Choose keyboard") { getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
        label("Try dictation")
        field("Tap here to try the Vaani keyboard", multiline = true).apply {
            importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO
            setSaveEnabled(false)
        }
        label("This practice text is temporary and is not saved.")
        label("Audio goes to Sarvam only during dictation. No audio or transcript history is saved. Password fields disable dictation.")
        sarvam = field("Sarvam API key", true)
        language = spinner("Language", Preferences.languages.map(SpeechChoices::language))
        mode = spinner("Output", Preferences.modes.map(SpeechChoices::output))
        label("For Hinglish, choose Auto-detect and Romanized / Latin script to keep Hindi in Latin letters and preserve English words.")
        speechModel = spinner("Speech model", listOf("Saaras v3 Realtime", "Saaras v4"))
        label("Speech recognition hints in Dictionary can override this selection with Saaras v4 when explicitly enabled.")
        section("Microphones")
        microphone = spinner("Microphone · remembered for this audio setup", listOf(getString(R.string.choose_microphone)))
        profiles = spinner("Microphone profile", listOf(getString(R.string.automatic_profile)))
        button("Use selected profile") { attempt {
            router.useProfile(profileIDs.getOrNull(profiles.selectedItemPosition)); refreshRouting(true); "Profile selected."
        } }
        profileName = field("Name a separate profile · Home, Office…")
        button("Save as separate microphone profile") { attempt {
            val uid = selectedMicrophoneUID() ?: error("Choose a microphone first.")
            router.createProfile(profileName.text.toString(), routeSnapshot, uid)
            refreshRouting(true); "Profile saved. It stays active until you choose Automatic."
        } }
        button("Forget active manual profile") { attempt {
            routeSnapshot.manualProfileID?.let { router.deleteProfile(it) } ?: error("Automatic matching is active.")
            refreshRouting(true); "Profile removed. Automatic matching restored."
        } }
        label("Unknown setups with several inputs ask for a choice. Bluetooth opens a communication route only during recording. Route changes stop capture; hardware behavior still needs device testing.")
        refreshRouting(true)
        button("Remember selected microphone") { attempt {
            val uid = selectedMicrophoneUID() ?: error("Choose a microphone first.")
            router.remember(routeSnapshot, uid); refreshRouting(true); "Microphone preference saved."
        } }
        section("Polish")
        enabled = Switch(this).apply { setText(R.string.polish_enabled); setTextColor(Color.WHITE) }; root.addView(enabled)
        endpoint = field("API base URL"); model = field("Processing model"); apiKey = field("Processing API key", true)
        reasoningEffort = spinner("Reasoning effort", Preferences.reasoningEffortNames)
        label("None turns reasoning off. Supported efforts depend on the model; Provider default leaves the setting unspecified.")
        serviceTier = spinner("Service tier", Preferences.serviceTierNames)
        label("Provider default leaves the tier unspecified. Fast / Priority may cost more; tier availability depends on your provider and model.")
        prompt = field("Post-processing prompt", multiline = true)
        section("Dictionary")
        label("Add the exact spelling you want for a name, word or short phrase. Examples: Vaani, Sarvam, Sudhanshu. Add each spelling separately; no commas, arrows or special format needed.")
        recognitionHints = Switch(this).apply {
            text = "Use dictionary as speech recognition hints"
            root.addView(this)
            setOnCheckedChangeListener { _, checked -> attempt {
                prefs.shared = prefs.shared.put("recognitionHintsEnabled", checked)
                "Speech recognition hints saved."
            } }
        }
        label("Off by default: hints can insert unrelated names in quiet or noisy speech. Polishing still uses your dictionary. Enabling hints with entries uses Saaras v4.")
        dictionaryEntry = field("Preferred spelling · e.g. Vaani")
        val dictionaryActions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        dictionaryAdd = actionButton("Add spelling") { saveDictionaryEntry() }
        dictionaryCancel = actionButton("Cancel edit") { resetDictionaryEntry() }.apply { visibility = View.GONE }
        dictionaryActions.addView(dictionaryAdd, LinearLayout.LayoutParams(0, dp(48), 1f))
        dictionaryActions.addView(dictionaryCancel, LinearLayout.LayoutParams(-2, dp(48)))
        root.addView(dictionaryActions)
        dictionaryCount = label("")
        dictionaryList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(dictionaryList)
        label("These spellings guide optional polishing. They affect speech recognition only when hints are enabled; they are not forced replacements.")
        section("Devices")
        button("Import shared settings…") { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "application/json"; addCategory(Intent.CATEGORY_OPENABLE) }, 20) }
        button("Save & export shared settings…") {
            attempt { save(); startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { type = "application/json"; addCategory(Intent.CATEGORY_OPENABLE); putExtra(Intent.EXTRA_TITLE, "vaani-settings.json") }, 21); "Choose a destination." }
        }
        label("Sync now · Tailscale", 22f)
        label("On Mac, open Vaani → Devices and Start sharing. Copy its pairing code here once. Both devices must be connected to Tailscale.")
        pairing = field("Pairing code from your Mac", true)
        syncStatus = label("")
        button("Pair with Mac") { syncAttempt {
            check(!syncBusy) { "Wait for the current sync to finish." }
            val peer = SyncPairing.parse(pairing.text.toString().trim())
            prefs.saveKey("settings-sync-peer", peer.json().toString()); pairing.text.clear()
            refreshPairingStatus(); "Paired with ${peer.host}. Tap Sync now to exchange settings."
        } }
        button("Sync now") { syncNow() }
        button("Forget paired Mac") { syncAttempt {
            check(!syncBusy) { "Wait for the current sync to finish." }
            prefs.saveKey("settings-sync-peer", ""); pairing.text.clear(); refreshPairingStatus(); "Pairing removed from Android. Revoke it on Mac to invalidate the code."
        } }
        label("Transfers language, dictionary, prompt and provider settings with authenticated encryption. Review which device's settings to use each time. API keys, microphone choices, audio and transcripts stay on their device.")
        refreshPairingStatus()
        root = shell
        button("Save settings & keys") { attempt { save(); "Saved. Keys stay on this device." } }
        attempt { load(); "Keys stay on this device." }
        selectSection(savedInstanceState?.getString("section") ?: intent.getStringExtra("section")?.takeIf { it in sections } ?: "Voice")
    }
    private fun section(name: String) {
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; visibility = View.GONE }
        sections[name] = root; sectionContainer.addView(root)
        label(name, 22f)
    }
    private fun selectSection(name: String) {
        if (name !in sections) return
        sectionOffsets[currentSection] = sectionScroll.scrollY
        currentFocus?.let { focus ->
            getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(focus.windowToken, 0)
            focus.clearFocus()
        }
        currentSection = name
        if (name == "Microphones") refreshRouting()
        sections.forEach { (key, page) -> page.visibility = if (key == name) View.VISIBLE else View.GONE }
        sectionButtons.forEach { (key, tab) ->
            val selected = key == name
            tab.isSelected = selected
            tab.backgroundTintList = android.content.res.ColorStateList.valueOf(if (selected) Color.rgb(255, 156, 87) else Color.rgb(36, 38, 44))
            tab.setTextColor(if (selected) Color.rgb(20, 21, 25) else Color.WHITE)
        }
        sectionScroll.post { if (currentSection == name) sectionScroll.scrollTo(0, sectionOffsets[name] ?: 0) }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("section", currentSection)
        super.onSaveInstanceState(outState)
    }
    private fun load() {
        val shared = prefs.shared
        sarvam.setText(prefs.key("sarvam")); apiKey.setText(prefs.key("processing"))
        language.setSelection(Preferences.languages.indexOf(shared.getString("language")).coerceAtLeast(0))
        mode.setSelection(Preferences.modes.indexOf(shared.getString("mode")).coerceAtLeast(0))
        speechModel.setSelection(Preferences.speechModels.indexOf(shared.getString("sarvamModel")).coerceAtLeast(0))
        endpoint.setText(shared.getString("endpoint")); model.setText(shared.getString("model")); prompt.setText(shared.getString("prompt"))
        recognitionHints.isChecked = shared.optBoolean("recognitionHintsEnabled", false)
        enabled.isChecked = shared.getBoolean("processingEnabled")
        reasoningEffort.setSelection(Preferences.reasoningEfforts.indexOf(shared.getString("reasoningEffort")).coerceAtLeast(0))
        serviceTier.setSelection(Preferences.serviceTiers.indexOf(shared.optString("serviceTier", "")).coerceAtLeast(0))
        val words = shared.getJSONArray("dictionary")
        dictionaryWords.clear()
        dictionaryWords.addAll((0 until words.length()).map { words.getString(it) })
        resetDictionaryEntry(); renderDictionary()
    }
    private fun sharedDraft(): JSONObject = prefs.shared.put("language", Preferences.languages[language.selectedItemPosition]).put("mode", Preferences.modes[mode.selectedItemPosition])
            .put("sarvamModel", Preferences.speechModels[speechModel.selectedItemPosition])
            .put("endpoint", endpoint.text.toString().trim()).put("model", model.text.toString().trim())
            .put("prompt", prompt.text.toString()).put("processingEnabled", enabled.isChecked)
            .put("reasoningEffort", Preferences.reasoningEfforts[reasoningEffort.selectedItemPosition])
            .put("serviceTier", Preferences.serviceTiers[serviceTier.selectedItemPosition])
            .put("recognitionHintsEnabled", recognitionHints.isChecked)
            .put("dictionary", JSONArray(dictionaryWords))
    private fun resetDictionaryEntry() {
        dictionaryEditingIndex = null; dictionaryEntry.setText("")
        dictionaryAdd.text = "Add spelling"; dictionaryCancel.visibility = View.GONE
    }
    private fun saveDictionaryEntry() { attempt {
        val word = dictionaryEntry.text.toString().trim()
        require(word.isNotEmpty() && word.codePointCount(0, word.length) <= 120 && !word.contains('\n') && !word.contains('\r')) {
            "Use one spelling or short phrase, up to 120 characters."
        }
        val editing = dictionaryEditingIndex
        require(dictionaryWords.withIndex().none { it.index != editing && it.value.equals(word, ignoreCase = true) }) { "That spelling is already in your dictionary." }
        require(editing != null || dictionaryWords.size < 500) { "Dictionary is full. Remove an entry before adding another." }
        val next = dictionaryWords.toMutableList()
        if (editing == null) next.add(word) else next[editing] = word
        persistDictionary(next)
        "Spelling saved."
    } }
    private fun persistDictionary(words: List<String>) {
        val next = prefs.shared.put("dictionary", JSONArray(words))
        Preferences.validate(next); prefs.shared = next
        dictionaryWords.clear(); dictionaryWords.addAll(words)
        resetDictionaryEntry(); renderDictionary()
    }
    private fun renderDictionary() {
        dictionaryCount.text = "${dictionaryWords.size} / 500 entries · up to 120 characters each · saved automatically"
        dictionaryList.removeAllViews()
        if (dictionaryWords.isEmpty()) {
            dictionaryList.addView(TextView(this).apply { text = "No spellings yet. Add names, places or terms that dictation often gets wrong."; setTextColor(Color.LTGRAY); setPadding(0, dp(16), 0, dp(16)) })
        }
        dictionaryWords.forEachIndexed { index, word ->
            val row = LinearLayout(this).apply { gravity = android.view.Gravity.CENTER_VERTICAL }
            row.addView(TextView(this).apply { text = word; setTextColor(Color.WHITE); setTextIsSelectable(true) }, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(actionButton("Edit") {
                dictionaryEditingIndex = index; dictionaryEntry.setText(word); dictionaryEntry.requestFocus()
                dictionaryAdd.text = "Save spelling"; dictionaryCancel.visibility = View.VISIBLE
                sectionScroll.smoothScrollTo(0, 0)
            }, LinearLayout.LayoutParams(-2, dp(48)))
            row.addView(actionButton("Remove") { attempt {
                persistDictionary(dictionaryWords.filterIndexed { i, _ -> i != index }); "Spelling removed."
            } }, LinearLayout.LayoutParams(-2, dp(48)))
            dictionaryList.addView(row)
        }
    }
    private fun save() {
        val value = sharedDraft()
        Preferences.validate(value)
        selectedMicrophoneUID()?.let { router.remember(routeSnapshot, it) }
        prefs.saveKey("sarvam", sarvam.text.toString().trim()); prefs.saveKey("processing", apiKey.text.toString().trim())
        prefs.shared = value
    }
    private fun refreshPairingStatus() {
        try {
            val code = prefs.key("settings-sync-peer")
            syncStatus.text = if (code.isBlank()) "No Mac paired." else "Paired Mac · ${SyncPairing.parse(code).host}"
        } catch (_: Exception) { syncStatus.setText(R.string.sync_pairing_unreadable) }
    }
    private fun reportSync(text: String) { message.text = text; syncStatus.text = text }
    private fun syncAttempt(action: () -> String) {
        try { reportSync(action()) } catch (error: Exception) { reportSync(error.message ?: "Sync failed.") }
    }
    private fun syncNow() {
        if (syncBusy) return
        try {
            val pairingCode = prefs.key("settings-sync-peer")
            check(pairingCode.isNotBlank()) { "Pair with Mac first. Start sharing in Vaani on Mac, then paste its pairing code above." }
            val peer = SyncPairing.parse(pairingCode)
            save()
            val local = prefs.shared
            syncBusy = true; reportSync("Connecting to paired Mac…")
            Thread {
                try {
                    val snapshot = SettingsSyncClient(peer).fetch()
                    runOnUiThread {
                        syncBusy = false
                        if (isFinishing || isDestroyed) return@runOnUiThread
                        val remote = snapshot.settings
                        AlertDialog.Builder(this).setTitle("Choose settings for this sync")
                            .setMessage("Mac: ${peer.host}\n\nMac API destination: ${remote.getString("endpoint")}\nProcessing: ${remote.getBoolean("processingEnabled")} · ${remote.getString("model")}\nLanguage: ${remote.getString("language")} · ${remote.getString("mode")}\nDictionary: ${remote.getJSONArray("dictionary")}\n\nMac prompt:\n${remote.getString("prompt")}\n\nAndroid API destination: ${local.getString("endpoint")}\n\nUse Mac replaces shared settings on Android. Send Android requires review on Mac. Keys and microphone choices stay local.")
                            .setPositiveButton("Use Mac") { _, _ -> syncAttempt {
                                check(sharedDraft().toString() == local.toString()) { "Android settings changed. Sync now again." }
                                prefs.shared = remote; load(); "Mac settings applied on Android."
                            } }
                            .setNeutralButton("Send Android") { _, _ -> offerSettings(peer, snapshot, local) }
                            .setNegativeButton("Cancel", null).show()
                        reportSync("Review sync direction and provider destination.")
                    }
                } catch (error: Exception) {
                    runOnUiThread { syncBusy = false; if (!isDestroyed) reportSync("Sync failed. Check Tailscale, Mac sharing and pairing. ${error.message ?: ""}") }
                }
            }.start()
        } catch (error: Exception) { reportSync(error.message ?: "Pair with Mac first.") }
    }
    private fun offerSettings(peer: SyncPairing, snapshot: SyncSnapshot, local: JSONObject) {
        if (syncBusy) return
        if (sharedDraft().toString() != local.toString()) {
            reportSync("Android settings changed. Sync now again to review the latest settings.")
            return
        }
        syncBusy = true; reportSync("Sending settings to Mac for review…")
        Thread {
            val result = try { SettingsSyncClient(peer).offer(snapshot, local) }
                catch (error: Exception) { error.message ?: "Could not send settings. Check Tailscale and Mac sharing." }
            runOnUiThread { syncBusy = false; if (!isDestroyed) reportSync(result) }
        }.start()
    }
    @Deprecated("Platform document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        attempt {
            if (requestCode == 20) {
                val imported = contentResolver.openInputStream(uri)?.use(SharedSettingsFile::read) ?: error("Could not read file")
                AlertDialog.Builder(this).setTitle("Import shared settings?")
                    .setMessage("Replaces language, prompt, dictionary and provider settings.\nAPI destination: ${imported.getString("endpoint")}\nProcessing: ${imported.getBoolean("processingEnabled")}\nKeys stay on this device.")
                    .setPositiveButton("Import") { _, _ -> attempt { prefs.shared = imported; load(); "Imported." } }.setNegativeButton("Cancel", null).show()
                "Review the import destination."
            } else {
                val bytes = SharedSettingsFile.encode(prefs.shared)
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("Could not write file")
                "Exported without credentials."
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        message.text = when {
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> "Permission granted."
            requestCode == 10 -> "Microphone permission denied. Allow microphone access to use dictation."
            else -> "Bluetooth permission denied. Built-in and USB inputs remain available."
        }
        refreshRouting(true)
    }
    override fun onResume() {
        super.onResume()
        getSystemService(AudioManager::class.java).registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
        refreshRouting()
    }
    override fun onPause() {
        getSystemService(AudioManager::class.java).unregisterAudioDeviceCallback(deviceCallback)
        super.onPause()
    }
    private fun selectedMicrophoneUID() = routeSnapshot.inputs.getOrNull(microphone.selectedItemPosition - 1)?.uid
    private fun refreshRouting(force: Boolean = false) {
        if (!::microphone.isInitialized) return
        try {
            val snapshot = router.snapshot()
            // Saved choices can change in the inline keyboard while this Activity stays alive.
            // Keep unsaved selections only while the complete routing state is unchanged.
            if (!force && ::routeSnapshot.isInitialized && routeSnapshot == snapshot) return
            routeSnapshot = snapshot
            microphone.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item,
                listOf(getString(R.string.choose_microphone)) + snapshot.inputs.map { it.label })
            val chosen = (snapshot.decision as? MicrophoneDecision.Selected)?.microphone?.uid
            microphone.setSelection(snapshot.inputs.indexOfFirst { it.uid == chosen } + 1)
            val savedProfiles = router.profiles()
            profileIDs = listOf(null) + savedProfiles.map { it.id }
            profiles.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item,
                listOf(getString(R.string.automatic_profile)) + savedProfiles.map { it.name })
            profiles.setSelection(profileIDs.indexOf(snapshot.manualProfileID).coerceAtLeast(0))
        } catch (error: Exception) { message.text = error.message }
    }
    private fun attempt(action: () -> String) { try { message.text = action() } catch (error: Exception) { message.text = error.message ?: "Operation failed" } }
    private fun label(value: String, size: Float = 14f) = TextView(this).apply { text = value; textSize = size; setTextColor(Color.WHITE); setPadding(0, 16, 0, 16); root.addView(this) }
    private fun field(hintText: String, secret: Boolean = false, multiline: Boolean = false) = EditText(this).apply {
        hint = hintText; setTextColor(Color.WHITE); setHintTextColor(Color.GRAY)
        inputType = if (secret) InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_CLASS_TEXT or (if (multiline) InputType.TYPE_TEXT_FLAG_MULTI_LINE else 0)
        if (multiline) minLines = 4
        root.addView(this, LinearLayout.LayoutParams(-1, -2))
    }
    private fun spinner(title: String, values: List<String>): Spinner {
        label(title)
        return Spinner(this).apply { adapter = ArrayAdapter(this@SettingsActivity, android.R.layout.simple_spinner_dropdown_item, values); root.addView(this) }
    }
    private fun actionButton(title: String, action: () -> Unit) = Button(this).apply {
        text = title; isAllCaps = false; setTextColor(Color.WHITE)
        backgroundTintList = android.content.res.ColorStateList.valueOf(Color.rgb(52, 54, 62))
        setOnClickListener { action() }
    }
    private fun button(title: String, action: () -> Unit) { root.addView(actionButton(title, action)) }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
