package dev.vaani.keyboard

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SpeechTranscriptTest {
    private fun event(type: String, index: Int, text: String) = JSONObject().put("event", "transcript.$type").put("utterance_idx", index).put("text", text)
    @Test fun partialsReplaceAndFinalsDeduplicate() {
        val transcript = SpeechTranscript()
        transcript.receive(event("partial", 0, "kal"))
        transcript.receive(event("partial", 0, "kal office"))
        assertEquals("kal office", transcript.text())
        assertTrue(transcript.hasPendingPartial())
        assertEquals("", transcript.text(finalOnly = true))
        transcript.receive(event("final", 0, "Kal office jaana hai."))
        transcript.receive(event("final", 0, "Kal office jaana hai."))
        transcript.receive(event("partial", 0, "late partial"))
        assertEquals("Kal office jaana hai.", transcript.text())
        assertFalse(transcript.hasPendingPartial())
    }
    @Test fun finalizationKeepsUtterancesInSpeechOrder() {
        val transcript = SpeechTranscript()
        transcript.receive(event("final", 1, "second")); transcript.receive(event("final", 0, "first"))
        transcript.receive(event("partial", 2, "third"))
        assertEquals("first second", transcript.text(true))
        assertEquals("first second third", transcript.text())
    }
    @Test fun malformedEventCannotCorruptCapturedText() {
        val transcript = SpeechTranscript()
        transcript.receive(event("final", 0, "preserved"))
        assertThrows(IllegalArgumentException::class.java) { transcript.receive(event("partial", -1, "invalid")) }
        assertEquals("preserved", transcript.text())
    }
}
