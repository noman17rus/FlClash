package com.follow.clash

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WdttFailoverPolicyTest {
    @Test
    fun `short outages do not start backup`() {
        val policy = WdttFailoverPolicy()
        assertFalse(policy.sample(false, 0))
        assertFalse(policy.sample(false, 5_000))
        assertFalse(policy.sample(true, 8_000))
        assertFalse(policy.sample(false, 9_000))
    }

    @Test
    fun `confirmed failure starts backup and recovery needs two successes`() {
        val policy = WdttFailoverPolicy()
        assertFalse(policy.sample(false, 0))
        assertTrue(policy.sample(false, 8_000))
        assertTrue(policy.sample(true, 12_000))
        assertTrue(policy.sample(false, 17_000))
        assertTrue(policy.sample(true, 22_000))
        assertFalse(policy.sample(true, 27_000))
    }

    @Test
    fun `network handover forgets failures and waits for stabilization`() {
        val policy = WdttFailoverPolicy()
        policy.sample(false, 0)
        policy.networkChanged(7_000)
        assertFalse(policy.canProbe(10_999))
        assertTrue(policy.canProbe(11_000))
        assertFalse(policy.sample(false, 11_000))
        assertTrue(policy.sample(false, 19_000))
    }

    @Test
    fun `network loss preserves backup and resets recovery evidence`() {
        val policy = WdttFailoverPolicy()
        policy.sample(false, 0)
        policy.sample(false, 8_000)
        policy.sample(true, 10_000)
        policy.networkChanged(11_000)
        assertTrue(policy.backup)
        assertTrue(policy.sample(true, 15_000))
        assertFalse(policy.sample(true, 20_000))
    }
}
