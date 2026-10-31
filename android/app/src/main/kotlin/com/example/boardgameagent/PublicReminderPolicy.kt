package com.example.boardgameagent

/** Decisions are local to one service origin; no account identifier is involved. */
internal object PublicReminderPolicy {
    enum class Decision { IGNORE, SAVE, NOTIFY }

    fun matchesAndroidRelease(channel: Any?, platform: Any?, architecture: Any?,
        supported: Set<String>): Boolean = channel == "stable" && platform == "android" &&
        architecture is String && (architecture == "any" || architecture in supported)

    fun catalog(previous: Long?, current: Long): Decision = when {
        current < 0 -> Decision.IGNORE
        previous == null -> Decision.SAVE
        current <= previous -> Decision.IGNORE
        else -> Decision.NOTIFY
    }

    fun release(previous: Long?, current: Long, installed: Long): Decision = when {
        current <= 0 || current <= (previous ?: 0) -> Decision.IGNORE
        current <= installed -> Decision.SAVE
        else -> Decision.NOTIFY
    }
}
