package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import java.util.Map;
import org.junit.jupiter.api.Test;

class LongHistogramTest {
    @Test void remainsBoundedWhileCountingEveryObservation() {
        LongHistogram histogram = new LongHistogram(32);
        for (int value = 1; value <= 100_000; value++) histogram.record(value);
        Map<String, Object> snapshot = histogram.snapshotMicros();
        assertEquals(100_000L, snapshot.get("observations"));
        assertEquals(32, snapshot.get("reservoirSize"));
        assertEquals(32, histogram.capacity());
        assertTrue((double) snapshot.get("maxMicros") > 0.0d);
    }

    @Test void rejectsZeroCapacity() {
        assertThrows(IllegalArgumentException.class, () -> new LongHistogram(0));
    }

    @Test void rawSnapshotDoesNotScaleByteValues() {
        LongHistogram histogram = new LongHistogram(8);
        histogram.record(66_584);
        Map<String, Object> snapshot = histogram.snapshotRaw();
        assertEquals(66_584.0d, snapshot.get("p50"));
        assertEquals(66_584.0d, snapshot.get("average"));
    }
}
