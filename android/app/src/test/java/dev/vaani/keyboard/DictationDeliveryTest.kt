package dev.vaani.keyboard

import org.junit.Assert.*
import org.junit.Test

class DictationDeliveryTest {
    @Test fun successfulFinalInsertsOnceWithoutReview() {
        val delivery = DictationDelivery()
        val commits = mutableListOf<String>()
        assertEquals(DictationDelivery.Outcome.INSERTED, delivery.complete("Kal office jaana hai", null, false) { commits.add(it) })
        assertEquals(DictationDelivery.Outcome.EMPTY, delivery.insert(false) { commits.add(it) })
        assertEquals(listOf("Kal office jaana hai"), commits)
        assertEquals("", delivery.pending)
    }
    @Test fun unfinishedOrFailedSpeechNeedsExplicitRecovery() {
        val delivery = DictationDelivery()
        assertEquals(DictationDelivery.Outcome.REVIEW, delivery.complete("preserved words", "Unfinalized speech", false) { fail("Must not insert"); true })
        assertEquals("preserved words", delivery.pending)
        assertEquals(DictationDelivery.Outcome.INSERTED, delivery.insert(false) { it == "preserved words" })
    }
    @Test fun failedEditorCommitRetainsTextForRetry() {
        val delivery = DictationDelivery()
        assertEquals(DictationDelivery.Outcome.FAILED, delivery.complete("Vaani", null, false) { false })
        assertEquals("Vaani", delivery.pending)
        assertEquals(DictationDelivery.Outcome.INSERTED, delivery.insert(false) { true })
        assertEquals("", delivery.pending)
    }
    @Test fun protectedFieldRejectsNewAndPendingText() {
        val delivery = DictationDelivery()
        assertEquals(DictationDelivery.Outcome.PROTECTED, delivery.complete("private", null, true) { fail("Password"); true })
        delivery.complete("old draft", "Needs review", false) { false }
        assertEquals(DictationDelivery.Outcome.PROTECTED, delivery.insert(true) { fail("Password"); true })
        assertEquals("", delivery.pending)
    }
    @Test fun emptyAndCancelledResultsCannotInsert() {
        val delivery = DictationDelivery()
        assertEquals(DictationDelivery.Outcome.EMPTY, delivery.complete(" ", null, false) { fail("Empty"); true })
        delivery.complete("old draft", "Needs review", false) { false }
        delivery.clear()
        assertEquals(DictationDelivery.Outcome.EMPTY, delivery.insert(false) { fail("Cancelled"); true })
    }
}
