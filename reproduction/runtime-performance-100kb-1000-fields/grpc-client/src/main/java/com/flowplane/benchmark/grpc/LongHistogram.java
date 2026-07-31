package com.flowplane.benchmark.grpc;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** A bounded-memory reservoir used for observational percentiles. */
final class LongHistogram {
    private final long[] reservoir;
    private final AtomicInteger size = new AtomicInteger();
    private long seen;
    private long sum;
    private long max;

    LongHistogram(int capacity) {
        if (capacity < 1) throw new IllegalArgumentException("capacity must be positive");
        this.reservoir = new long[capacity];
    }

    synchronized void record(long value) {
        if (value < 0) return;
        seen++;
        sum += value;
        max = Math.max(max, value);
        int currentSize = size.get();
        if (currentSize < reservoir.length) {
            reservoir[currentSize] = value;
            size.incrementAndGet();
        } else {
            // Deterministic uniform-ish replacement. It is reproducible and never grows.
            long mixed = mix64(seen);
            long slot = Long.remainderUnsigned(mixed, seen);
            if (slot < reservoir.length) reservoir[(int) slot] = value;
        }
    }

    synchronized Map<String, Object> snapshotMicros() {
        return snapshot(1_000.0d, "Micros");
    }

    synchronized Map<String, Object> snapshotRaw() {
        return snapshot(1.0d, "");
    }

    private Map<String, Object> snapshot(double divisor, String suffix) {
        int length = size.get();
        if (length == 0) return Map.of("observations", seen, "reservoirSize", 0);
        long[] sorted = Arrays.copyOf(reservoir, length);
        Arrays.sort(sorted);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("observations", seen);
        result.put("reservoirSize", length);
        result.put("average" + suffix, (sum / (double) seen) / divisor);
        result.put("p50" + suffix, percentile(sorted, 0.50d) / divisor);
        result.put("p95" + suffix, percentile(sorted, 0.95d) / divisor);
        result.put("p99" + suffix, percentile(sorted, 0.99d) / divisor);
        result.put("p999" + suffix, percentile(sorted, 0.999d) / divisor);
        result.put("max" + suffix, max / divisor);
        return result;
    }

    int capacity() { return reservoir.length; }

    private static long percentile(long[] sorted, double percentile) {
        int index = Math.min(sorted.length - 1, Math.max(0, (int) Math.ceil(sorted.length * percentile) - 1));
        return sorted[index];
    }

    private static long mix64(long value) {
        value = (value ^ (value >>> 30)) * 0xbf58476d1ce4e5b9L;
        value = (value ^ (value >>> 27)) * 0x94d049bb133111ebL;
        return value ^ (value >>> 31);
    }
}
