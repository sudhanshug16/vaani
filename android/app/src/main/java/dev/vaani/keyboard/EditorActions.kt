package dev.vaani.keyboard

import android.icu.text.BreakIterator
import android.view.KeyEvent
import android.view.inputmethod.InputConnection
import java.util.Locale

/** Editing stays local: surrounding text is never retained or sent to speech services. */
object EditorActions {
    private const val CONTEXT_LIMIT = 4096

    fun backspace(connection: InputConnection): Boolean {
        connection.beginBatchEdit()
        try {
            if (!connection.getSelectedText(0).isNullOrEmpty()) return connection.commitText("", 1)
            val before = connection.getTextBeforeCursor(CONTEXT_LIMIT, 0)
                ?: return sendDeleteKey(connection)
            if (before.isEmpty()) return sendDeleteKey(connection)
            val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
            iterator.setText(before.toString())
            val boundary = iterator.preceding(before.length)
            // A cluster may extend beyond our bounded context. Refuse to split it.
            if (boundary == BreakIterator.DONE || (boundary == 0 && before.length == CONTEXT_LIMIT)) return false
            return connection.deleteSurroundingText(before.length - boundary, 0)
        } finally {
            connection.endBatchEdit()
        }
    }

    private fun sendDeleteKey(connection: InputConnection): Boolean {
        val down = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        val up = connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        return down && up
    }
}
