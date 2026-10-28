package dev.vaani.keyboard

import org.junit.Assert.*
import org.junit.Test

class RoutingTest {
    private val builtin = MicrophoneOption("builtin", "Phone", 1, 15, "")
    private val usb = MicrophoneOption("usb", "Desk mic", 2, 11, "usb-address")
    @Test fun unfamiliarMultipleInputsAskRatherThanUseSystemDefault() {
        assertEquals(MicrophoneDecision.Ask, MicrophonePolicy.decide(listOf(builtin, usb), null))
        assertEquals(MicrophoneDecision.Selected(builtin), MicrophonePolicy.decide(listOf(builtin), null))
        assertEquals(MicrophoneDecision.Unavailable, MicrophonePolicy.decide(emptyList(), null))
    }
    @Test fun rememberedMicrophoneSurvivesDeviceEnumerationOrderAndPortIDChanges() {
        val reconnected = usb.copy(deviceId = 87)
        assertEquals(MicrophoneDecision.Selected(reconnected), MicrophonePolicy.decide(listOf(reconnected, builtin), "usb"))
        assertEquals(MicrophoneDecision.Missing, MicrophonePolicy.decide(listOf(builtin), "usb"))
    }
    @Test fun duplicateIdentitiesNeverPretendToSelectOneDevice() {
        assertEquals(MicrophoneDecision.AmbiguousIdentity, MicrophonePolicy.decide(listOf(usb, usb.copy(deviceId = 9)), "usb"))
    }
    @Test fun builtInLocationsAreReadableWithoutChangingRoutingIdentity() {
        val back = builtin.copy(uid = "back", address = "back")
        val bottom = builtin.copy(uid = "bottom", address = "bottom")
        val labels = MicrophonePolicy.displayLabels(listOf(back, bottom))
        assertEquals(listOf("Phone · Back", "Phone · Bottom"), labels.map { it.label })
        assertEquals(listOf(back, bottom), labels.mapIndexed { i, mic -> mic.copy(label = listOf(back, bottom)[i].label) })
        assertEquals(MicrophoneDecision.Selected(labels[1]), MicrophonePolicy.decide(labels, "bottom"))
    }
    @Test fun sameNameInputsHaveStableDistinctLabelsAcrossOrderAndDeviceIDs() {
        val second = usb.copy(uid = "other-usb", deviceId = 3, address = "other-address")
        val original = MicrophonePolicy.displayLabels(listOf(usb, second)).associate { it.uid to it.label }
        val returned = MicrophonePolicy.displayLabels(listOf(second.copy(deviceId = 27), usb.copy(deviceId = 87))).associate { it.uid to it.label }
        assertEquals(original, returned)
        assertEquals(2, original.values.toSet().size)
        assertEquals(usb.label, MicrophonePolicy.displayLabels(listOf(usb)).single().label)
    }
    @Test fun duplicateIdentitiesRemainAmbiguousDespiteDisplayLabels() {
        val duplicate = MicrophonePolicy.displayLabels(listOf(usb, usb.copy(deviceId = 9)))
        assertTrue(duplicate.all { it.label.contains("Cannot distinguish") })
        assertEquals(MicrophoneDecision.AmbiguousIdentity, MicrophonePolicy.decide(duplicate, usb.uid))
        val mixed = MicrophonePolicy.displayLabels(listOf(usb, usb.copy(deviceId = 9), usb.copy(uid = "other", deviceId = 3)))
        assertEquals(2, mixed.count { it.label.contains("Cannot distinguish") })
        assertEquals(2, mixed.map { it.label }.toSet().size)
        val unknownAddress = builtin.copy(address = "vendor-specific-location")
        assertEquals(builtin.label, MicrophonePolicy.displayLabels(listOf(unknownAddress)).single().label)
    }
    @Test fun setupIdentityIgnoresEnumerationOrderButIncludesOutputs() {
        assertEquals(MicrophonePolicy.fingerprint(listOf("a", "b"), listOf("hub", "speaker")),
            MicrophonePolicy.fingerprint(listOf("b", "a"), listOf("speaker", "hub")))
        assertNotEquals(MicrophonePolicy.fingerprint(listOf("a"), listOf("hdmi")), MicrophonePolicy.fingerprint(listOf("a"), emptyList()))
        assertNotEquals(MicrophonePolicy.identity(1, "a|b", "c"), MicrophonePolicy.identity(1, "a", "b|c"))
    }
    @Test fun startupFramesAreDiscardedUntilExpectedRouteIsConfirmed() {
        val verifier = RecordingRouteVerifier(9, 2000)
        assertFalse(verifier.accept(null, 0))
        assertFalse(verifier.accept(1, 100))
        assertTrue(verifier.accept(9, 200))
        assertTrue(verifier.accept(9, 300))
    }
    @Test fun routingAwayAfterConfirmationStopsBeforeFramesAreAccepted() {
        val verifier = RecordingRouteVerifier(9, 2000)
        verifier.accept(9, 100)
        assertThrows(IllegalStateException::class.java) { verifier.accept(1, 150) }
        assertThrows(IllegalStateException::class.java) { verifier.accept(null, 150) }
    }
    @Test fun startupTimeoutNeverAcceptsUnverifiedInput() {
        assertThrows(IllegalStateException::class.java) { RecordingRouteVerifier(9, 2000).accept(1, 2000) }
    }
}
