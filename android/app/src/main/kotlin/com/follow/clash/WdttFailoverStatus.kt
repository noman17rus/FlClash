package com.follow.clash

internal class WdttFailoverStatus(private val wallClock: () -> Long = System::currentTimeMillis) {
    private var group: String? = null
    private var phase = "checking"
    private var route: String? = null
    private var switchedAt: Long? = null
    private var vlessAvailable: Boolean? = null
    private var measuredRevision: Long? = null
    private var measuredGroup: String? = null
    private val events = ArrayDeque<Map<String, Any>>()

    @Synchronized
    fun primaryMeasured(available: Boolean, revision: Long, profileGroup: String? = group) {
        vlessAvailable = available
        measuredRevision = revision
        measuredGroup = profileGroup
    }

    @Synchronized
    fun byeDpiUnavailable(cellular: Boolean, revision: Long): Boolean =
        cellular && measuredRevision == revision && measuredGroup == group && vlessAvailable == false

    @Synchronized
    fun update(group: String? = this.group, phase: String, route: String? = this.route) {
        val now = wallClock()
        if (route != this.route) switchedAt = now
        if (phase != this.phase || events.isEmpty()) {
            events.addFirst(mapOf("phase" to phase, "time" to now))
            while (events.size > 8) events.removeLast()
        }
        this.group = group
        this.phase = phase
        this.route = route
    }

    @Synchronized
    fun snapshot(): Map<String, Any?> = mapOf(
        "group" to group,
        "phase" to phase,
        "route" to route,
        "switchedAt" to switchedAt,
        "events" to events.toList(),
    )
}
