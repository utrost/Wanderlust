import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteBlobTooBigException;
public class MapCursorProbe {
 public static void main(String[] args) {
  SQLiteDatabase db=SQLiteDatabase.create(null);
  db.execSQL("CREATE TABLE offline_area(version TEXT PRIMARY KEY, geojson TEXT)");
  StringBuilder value=new StringBuilder();
  for(int i=0;i<700000;i++) value.append("Straße🌍");
  String source=value.toString();
  db.execSQL("INSERT INTO offline_area VALUES (?,?)",new Object[]{"test",source});
  boolean rejected=false;
  try(Cursor c=db.rawQuery("SELECT geojson FROM offline_area WHERE version = ?",new String[]{"test"})) {
   c.moveToFirst(); c.getString(0);
  } catch(SQLiteBlobTooBigException e) {
   rejected=true; System.out.println("OLD_READ_REPRODUCED: "+e.getMessage());
  }
  if(!rejected) throw new AssertionError("Expected oversized row rejection");
  int length;
  try(Cursor c=db.rawQuery("SELECT length(geojson) AS characters FROM offline_area WHERE version = ?",new String[]{"test"})) {
   c.moveToFirst();length=c.getInt(0);
  }
  StringBuilder restored=new StringBuilder(); int chunks=0;
  for(int start=1;start<=length;start+=131072) {
   try(Cursor c=db.rawQuery("SELECT substr(geojson, ?, ?) AS chunk FROM offline_area WHERE version = ?",new String[]{""+start,"131072","test"})) {
    c.moveToFirst();restored.append(c.getString(0));chunks++;
   }
  }
  if(!source.equals(restored.toString())) throw new AssertionError("Mismatch");
  System.out.println("CHUNKED_READ_OK: "+chunks+" chunks, "+source.length()+" UTF-16 units, exact Unicode round trip");
  db.close();
 }
}
