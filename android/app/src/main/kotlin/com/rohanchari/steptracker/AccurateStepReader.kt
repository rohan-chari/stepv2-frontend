package com.rohanchari.steptracker

internal data class ManualStepPage(val manualSteps: Long, val nextToken: String?)

/** Completeness is required before publishing: read errors cannot turn into zero manual steps. */
internal suspend fun readAccurateStepTotal(
    aggregate: suspend () -> Long,
    maxPages: Int = 100,
    readPage: suspend (String?) -> ManualStepPage,
): Int {
    val total = aggregate()
    var manual = 0L
    var token: String? = null
    val seen = mutableSetOf<String>()
    repeat(maxPages) {
        val page = readPage(token)
        require(page.manualSteps >= 0) { "Invalid manual steps" }
        manual = Math.addExact(manual, page.manualSteps)
        token = page.nextToken
        if (token.isNullOrEmpty()) {
            return (total - manual).coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }
        check(seen.add(token!!)) { "Health Connect repeated a page token" }
    }
    error("Health Connect record page limit exceeded; refusing incomplete total")
}
