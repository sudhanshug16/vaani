package dev.vaani.keyboard

import org.junit.Assert.*
import org.junit.Test

class CommunicationRouteLeaseTest {
    private class Port : CommunicationRoutePort {
        override var mode = 0
        var requested: Int? = null
        var clears = 0
        var accepted = true
        var throwRequest = false
        var throwClear = false
        override fun request(deviceId: Int): Boolean {
            requested = deviceId
            if (throwRequest) error("Route failure")
            return accepted
        }
        override fun clear() { requested = null; clears++; if (throwClear) error("Cleanup failure") }
    }
    @Test fun releasesItsRequestAndModeOnceOnClose() {
        val port = Port()
        val lease = CommunicationRouteLease.acquire(port, 42, 0, 3)
        assertEquals(3, port.mode); assertEquals(42, port.requested)
        lease.close(); lease.close()
        assertNull(port.requested); assertEquals(1, port.clears); assertEquals(0, port.mode)
    }
    @Test fun rejectedRouteCleansUpItsModeAndPartialRequest() {
        val port = Port().apply { accepted = false }
        assertThrows(IllegalStateException::class.java) { CommunicationRouteLease.acquire(port, 42, 0, 3) }
        assertEquals(0, port.mode); assertEquals(1, port.clears); assertNull(port.requested)
    }
    @Test fun thrownRouteErrorAlsoRestoresAudioMode() {
        val port = Port().apply { throwRequest = true }
        assertThrows(IllegalStateException::class.java) { CommunicationRouteLease.acquire(port, 42, 0, 3) }
        assertEquals(0, port.mode); assertEquals(1, port.clears)
    }
    @Test fun cleanupFailureDoesNotSkipModeRelease() {
        val port = Port()
        val lease = CommunicationRouteLease.acquire(port, 42, 0, 3)
        port.throwClear = true
        assertThrows(IllegalStateException::class.java) { lease.close() }
        assertEquals(0, port.mode)
    }
    @Test fun existingCallIsNotTakenOver() {
        val port = Port().apply { mode = 2 }
        assertThrows(IllegalStateException::class.java) { CommunicationRouteLease.acquire(port, 42, 0, 3) }
        assertEquals(2, port.mode); assertNull(port.requested); assertEquals(0, port.clears)
    }
}
