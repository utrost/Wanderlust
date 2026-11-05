package com.simiono.wanderlust

import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35], manifest=Config.NONE)
class MapDiagnosticsTest {
    @Test fun `metadata is available without location or storage grants`() {
        val context = RuntimeEnvironment.getApplication()
        val result = MapDiagnostics.environment(context)
        assertEquals(35, result["sdk"])
        assertEquals(File(context.filesDir, "map-diagnostics").path, result["directory"])
        assertTrue(result.containsKey("model"))
        assertTrue(result.containsKey("build"))
        assertTrue(result.containsKey("availableBytes"))
        assertEquals(setOf("manufacturer", "model", "android", "sdk", "directory", "build", "availableBytes"), result.keys)
    }
}
