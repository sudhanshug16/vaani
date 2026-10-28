package dev.vaani.keyboard

/** Main-thread delivery. Failed/unfinalized results require an explicit retry;
 * successful commits clear pending text so they cannot be inserted twice. */
class DictationDelivery {
    var pending: String = ""
        private set
    enum class Outcome { INSERTED, EMPTY, REVIEW, FAILED, PROTECTED }
    fun complete(text: String, error: String?, protected: Boolean, commit: (String) -> Boolean): Outcome {
        pending = text
        if (protected) { clear(); return Outcome.PROTECTED }
        if (text.isBlank()) { clear(); return Outcome.EMPTY }
        if (error != null) return Outcome.REVIEW
        return insert(protected, commit)
    }
    fun insert(protected: Boolean, commit: (String) -> Boolean): Outcome {
        if (protected) { clear(); return Outcome.PROTECTED }
        if (pending.isBlank()) return Outcome.EMPTY
        if (!commit(pending)) return Outcome.FAILED
        clear()
        return Outcome.INSERTED
    }
    fun clear() { pending = "" }
}
