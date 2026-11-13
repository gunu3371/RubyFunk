package io.github.gunu3371.rubyfunk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pure JVM test of the launcher-file halves in Links.kt: the name a title saves under, and the
 * link a frontend's file hands back. Run: `./gradlew -PexcludeScreenshots :app:testDebugUnitTest`.
 */
class LinksTest {
    private val url = "rubyfunk://connect/abc?launch=steam:570"

    @Test
    fun aTitleSavesUnderANameEverySdCardTakes() {
        assertEquals("Halo Reach.rubyfunk", launcherFileName("Halo: Reach"))
        assertEquals("AC DC Live.rubyfunk", launcherFileName("AC/DC  Live?"))
        assertEquals("RubyFunk.rubyfunk", launcherFileName(" ... "))
    }

    @Test
    fun theFilesFirstNonBlankLineIsTheLink() {
        assertEquals(url, launcherFileLink("$url\n"))
        assertEquals(url, launcherFileLink("﻿\r\n  $url  \r\nignored"))
        assertEquals("pf://connect/abc", launcherFileLink("pf://connect/abc"))
    }

    @Test
    fun aFileWithNoLinkOfOursYieldsNone() {
        assertNull(launcherFileLink(""))
        assertNull(launcherFileLink("https://example.com/\n$url"))
        assertNull(launcherFileLink("[Desktop Entry]"))
    }

    @Test
    fun aLinkTheRoutersWillRefuseStillReachesThemToSayWhy() {
        assertEquals("rubyfunk://pair/abc", launcherFileLink("rubyfunk://pair/abc"))
    }
}
