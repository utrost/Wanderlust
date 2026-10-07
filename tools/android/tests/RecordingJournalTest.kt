package com.simiono.wanderlust

import android.database.sqlite.SQLiteDatabase
import android.location.Location
import org.json.JSONObject
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35], manifest=Config.NONE)
class RecordingJournalTest {
    private lateinit var file: File
    private lateinit var journal: RecordingJournal
    @Before fun setup() {
        file = File.createTempFile("wanderlust-native", ".db")
        SQLiteDatabase.openOrCreateDatabase(file, null).use { db ->
            db.execSQL("PRAGMA application_id=1463897668")
            db.execSQL("CREATE TABLE recorded_walk(id INTEGER PRIMARY KEY,started_at TEXT NOT NULL,ended_at TEXT,status TEXT NOT NULL,uid TEXT,trace_metadata TEXT NOT NULL DEFAULT '{}',fingerprint TEXT)")
            db.execSQL("CREATE TABLE recorded_point(walk_id INTEGER NOT NULL REFERENCES recorded_walk(id),seq INTEGER NOT NULL,position TEXT NOT NULL,timestamp TEXT NOT NULL,PRIMARY KEY(walk_id,seq))")
            db.execSQL("CREATE TRIGGER assign_walk_uid AFTER INSERT ON recorded_walk WHEN NEW.uid IS NULL BEGIN UPDATE recorded_walk SET uid=lower(hex(randomblob(16))) WHERE id=NEW.id; END")
        }
        journal = RecordingJournal(file.path)
    }
    @After fun close() { journal.close(); file.delete() }
    private fun fix(time: Long) = Location("gps").apply { latitude=53.0; longitude=8.8; accuracy=5f; this.time=time }
    @Test fun `native capture survives reconnection without duplicate points or sessions`() {
        val id = journal.start("walk", 1000, null)
        assertTrue(journal.append(id, fix(2000), 0.0, JSONObject()))
        assertFalse(journal.append(id, fix(2000), 0.0, JSONObject()))
        journal.close(); journal = RecordingJournal(file.path)
        assertEquals(id, journal.state()!!["walkId"])
        assertEquals(true, journal.state()!!["active"])
        assertEquals(1L, journal.state()!!["pointCount"])
        assertEquals(1, journal.points(id, -1).size)
        assertEquals(0, journal.points(id, 0).size)
        assertThrows(IllegalStateException::class.java) { journal.start("walk", 5000, null) }
        journal.start("walk", 5000, id)
        assertEquals(emptyList<Int>(), journal.state()!!["segments"])
        journal.append(id, fix(6000), 4.0, JSONObject())
        assertEquals(listOf(1), journal.state()!!["segments"])
        assertEquals(2L, journal.state()!!["pointCount"])
    }
    @Test fun `stop is durable idempotent and rejects old notifications`() {
        val first = journal.start("walk", 1000, null)
        journal.append(first, fix(2000), 0.0, JSONObject())
        assertTrue(journal.finish(first, 3000, false))
        assertFalse(journal.finish(first, 4000, false))
        assertFalse(journal.append(first, fix(5000), 5.0, JSONObject()))
        val second = journal.start("cycle", 6000, null)
        assertFalse(journal.finish(first, 7000, false))
        assertEquals(true, journal.state()!!["active"])
        assertEquals(second, journal.state()!!["walkId"])
        assertThrows(IllegalStateException::class.java) { journal.start("walk", 8000, first) }
    }
    @Test fun `interrupted finish ends at last saved fix not relaunch time`() {
        val id = journal.start("walk", 1000, null)
        journal.append(id, fix(2000), 2.0, JSONObject())
        journal.finish(id, 90000000, true)
        assertEquals(RecordingJournal.iso(2000), journal.state()!!["endedAt"])
        assertEquals("interrupted", journal.state()!!["status"])
    }
    @Test fun `failed metadata write rolls back point and sequence`() {
        val id = journal.start("walk", 1000, null)
        journal.db.execSQL("CREATE TRIGGER fail_update BEFORE UPDATE ON recorded_walk BEGIN SELECT RAISE(ABORT,'storage full'); END")
        assertThrows(Exception::class.java) { journal.append(id, fix(2000), 2.0, JSONObject()) }
        assertEquals(0L, journal.state()!!["pointCount"])
        journal.db.execSQL("DROP TRIGGER fail_update")
        assertTrue(journal.append(id, fix(2000), 2.0, JSONObject()))
        assertEquals(0, journal.points(id, -1).single()["sequence"])
    }
    @Test fun `deleting a finished walk releases native metadata`() {
        val id = journal.start("walk", 1000, null)
        journal.finish(id, 2000, false)
        journal.db.execSQL("DELETE FROM recorded_walk WHERE id=?", arrayOf(id))
        assertNull(journal.state())
    }
}
