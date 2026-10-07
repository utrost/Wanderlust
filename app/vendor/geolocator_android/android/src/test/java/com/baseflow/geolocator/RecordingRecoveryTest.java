package com.baseflow.geolocator;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import android.content.Context;
import android.location.Location;
import android.util.Log;
import com.baseflow.geolocator.location.GeolocationManager;
import com.baseflow.geolocator.location.LocationClient;
import com.baseflow.geolocator.location.LocationOptions;
import com.baseflow.geolocator.location.PositionChangedCallback;
import io.flutter.plugin.common.EventChannel;
import java.lang.reflect.Field;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

public class RecordingRecoveryTest {
  @Test
  public void recoveryPreservesForegroundSessionAndRejectsOldCallbacks() throws Exception {
    try (MockedStatic<Log> ignored = mockStatic(Log.class)) {
      GeolocatorLocationService service = mock(GeolocatorLocationService.class, CALLS_REAL_METHODS);
      Context context = mock(Context.class);
      doReturn(context).when(service).getApplicationContext();
      GeolocationManager manager = mock(GeolocationManager.class);
      LocationClient first = mock(LocationClient.class), second = mock(LocationClient.class);
      LocationOptions options = LocationOptions.parseArguments(null);
      EventChannel.EventSink events = mock(EventChannel.EventSink.class);
      when(manager.createLocationClient(context, false, options)).thenReturn(first, second);
      service.setGeolocationManager(manager);
      Field foreground = GeolocatorLocationService.class.getDeclaredField("isForeground");
      foreground.setAccessible(true);
      foreground.setBoolean(service, true);
      service.startLocationService(false, options, events);
      assertTrue(service.restartLocationUpdates());
      org.mockito.InOrder order = inOrder(manager);
      order.verify(manager).createLocationClient(context, false, options);
      order.verify(manager).startPositionUpdates(eq(first), isNull(), any(), any());
      order.verify(manager).stopPositionUpdates(first);
      order.verify(manager).createLocationClient(context, false, options);
      order.verify(manager).startPositionUpdates(eq(second), isNull(), any(), any());
      verify(service, never()).disableBackgroundMode();
      verify(service, never()).enableBackgroundMode(any());
      assertTrue(foreground.getBoolean(service));
      assertTrue(service.canStopLocationService(true)); // No extra session/listener.

      ArgumentCaptor<PositionChangedCallback> callbacks = ArgumentCaptor.forClass(PositionChangedCallback.class);
      verify(manager, times(2)).startPositionUpdates(any(), isNull(), callbacks.capture(), any());
      callbacks.getAllValues().get(0).onPositionChanged(mock(Location.class));
      verifyNoInteractions(events); // Late fix from the removed request.
      callbacks.getAllValues().get(1).onPositionChanged(mock(Location.class));
      verify(events).success(any());
      clearInvocations(events);
      service.stopLocationService();
      verify(manager).stopPositionUpdates(second);
      assertFalse(service.restartLocationUpdates());
      callbacks.getAllValues().get(1).onPositionChanged(mock(Location.class));
      verifyNoInteractions(events);
    }
  }

  @Test
  public void inactiveServiceCannotStartRecordingThroughRecovery() {
    GeolocatorLocationService service = mock(GeolocatorLocationService.class, CALLS_REAL_METHODS);
    assertFalse(service.restartLocationUpdates());
    verify(service, never()).enableBackgroundMode(any());
  }
}
