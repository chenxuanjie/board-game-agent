package com.example.boardgameagent

fun main() {
    val ignore = PublicReminderPolicy.Decision.IGNORE
    val save = PublicReminderPolicy.Decision.SAVE
    val notify = PublicReminderPolicy.Decision.NOTIFY
    check(PublicReminderPolicy.catalog(null, 8) == save)
    check(PublicReminderPolicy.catalog(8, 9) == notify)
    check(PublicReminderPolicy.catalog(8, 8) == ignore)
    check(PublicReminderPolicy.catalog(8, 7) == ignore)
    check(PublicReminderPolicy.catalog(null, -1) == ignore)
    check(PublicReminderPolicy.release(null, 49, 50) == save)
    check(PublicReminderPolicy.release(null, 51, 50) == notify)
    check(PublicReminderPolicy.release(51, 51, 50) == ignore)
    check(PublicReminderPolicy.release(51, 52, 50) == notify)
    check(PublicReminderPolicy.release(null, 0, 50) == ignore)
    check(PublicReminderPolicy.matchesAndroidRelease("stable", "android", "any", setOf("arm64")))
    check(PublicReminderPolicy.matchesAndroidRelease("stable", "android", "arm64", setOf("arm64")))
    check(!PublicReminderPolicy.matchesAndroidRelease("beta", "android", "any", setOf("arm64")))
    check(!PublicReminderPolicy.matchesAndroidRelease("stable", "windows", "any", setOf("arm64")))
    check(!PublicReminderPolicy.matchesAndroidRelease("stable", "android", "x64", setOf("arm64")))
    println("Public reminder version decisions passed")
}
