package com.flowplane.benchmark.measurement;

import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordingFile;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/** Summarizes bounded JFR allocation sampling without retaining individual events. */
public final class JfrAllocationSummaryCli {
    private JfrAllocationSummaryCli() {}

    public static void main(String[] args) throws Exception {
        Map<String, String> options = parse(args);
        String campaignId = required(options, "campaign-id");
        String runtimeType = required(options, "runtime-type");
        String artifactHash = required(options, "artifact-hash");
        if (!campaignId.matches("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")) throw new IllegalArgumentException("unsafe --campaign-id");
        if (!(runtimeType.equals("HTTP") || runtimeType.equals("GRPC") || runtimeType.equals("COMPETITOR")
            || runtimeType.equals("KAFKA_BROKER") || runtimeType.equals("SOURCE_PRODUCER"))) {
            throw new IllegalArgumentException("--runtime-type must identify a supported runtime or allocation component");
        }
        Path recording = Path.of(required(options, "recording")).toAbsolutePath().normalize();
        Path output = Path.of(required(options, "output")).toAbsolutePath().normalize();
        Instant windowStart = optionalInstant(options, "window-start");
        Instant windowEnd = optionalInstant(options, "window-end");
        if ((windowStart == null) != (windowEnd == null) || (windowStart != null && !windowEnd.isAfter(windowStart))) {
            throw new IllegalArgumentException("--window-start and --window-end must form an increasing pair");
        }
        long measuredOperations = options.containsKey("measured-operations")
            ? Long.parseLong(options.get("measured-operations")) : 0;
        if (measuredOperations < 0) throw new IllegalArgumentException("--measured-operations must be non-negative");
        if (!Files.isRegularFile(recording)) throw new IllegalArgumentException("JFR recording does not exist: " + recording);

        long sampledEvents = 0;
        long estimatedBytes = 0;
        Instant recordingFirst = null;
        Instant recordingLast = null;
        Instant allocationFirst = null;
        Instant allocationLast = null;
        try (RecordingFile file = new RecordingFile(recording)) {
            while (file.hasMoreEvents()) {
                RecordedEvent event = file.readEvent();
                Instant eventStart = event.getStartTime();
                Instant eventEnd = event.getEndTime();
                if (windowStart != null && (eventStart.isBefore(windowStart) || !eventStart.isBefore(windowEnd))) continue;
                if (recordingFirst == null || eventStart.isBefore(recordingFirst)) recordingFirst = eventStart;
                if (recordingLast == null || eventEnd.isAfter(recordingLast)) recordingLast = eventEnd;
                if (!"jdk.ObjectAllocationSample".equals(event.getEventType().getName())) continue;
                sampledEvents++;
                long weight = event.hasField("weight") ? event.getLong("weight") : 0;
                estimatedBytes = saturatingAdd(estimatedBytes, Math.max(0, weight));
                if (allocationFirst == null || eventStart.isBefore(allocationFirst)) allocationFirst = eventStart;
                if (allocationLast == null || eventStart.isAfter(allocationLast)) allocationLast = eventStart;
            }
        }

        long observedNanos = recordingFirst == null || recordingLast == null
            ? 0 : Math.max(0, Duration.between(recordingFirst, recordingLast).toNanos());
        long allocationSpanNanos = allocationFirst == null || allocationLast == null
            ? 0 : Math.max(0, Duration.between(allocationFirst, allocationLast).toNanos());
        double bytesPerSecond = observedNanos == 0 ? 0.0 : estimatedBytes / (observedNanos / 1_000_000_000.0);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("schemaVersion", 1);
        result.put("kind", "flowplane-benchmark-jfr-allocation-summary");
        result.put("campaignId", campaignId);
        result.put("runtimeType", runtimeType);
        result.put("artifactHash", artifactHash);
        result.put("recording", recording.toString());
        result.put("state", sampledEvents > 0 ? "available" : "unavailable");
        result.put("reason", sampledEvents > 0 ? "object_allocation_sample_weight" : "no_jdk_object_allocation_sample_events");
        result.put("sampledEventCount", sampledEvents);
        result.put("estimatedAllocatedBytes", estimatedBytes);
        result.put("estimatedBytesPerSecond", bytesPerSecond);
        result.put("recordingObservationNanos", observedNanos);
        result.put("allocationSampleSpanNanos", allocationSpanNanos);
        result.put("measurementWindowStart", windowStart == null ? null : windowStart.toString());
        result.put("measurementWindowEnd", windowEnd == null ? null : windowEnd.toString());
        result.put("measurementWindowApplied", windowStart != null);
        result.put("measuredOperations", measuredOperations == 0 ? null : measuredOperations);
        result.put("estimatedBytesPerOperation", measuredOperations == 0 ? null : estimatedBytes / (double) measuredOperations);
        result.put("estimate", true);
        result.put("capturedAt", Instant.now().toString());
        if (output.getParent() != null) Files.createDirectories(output.getParent());
        Files.writeString(output, Json.write(result) + System.lineSeparator(), StandardCharsets.UTF_8);
        System.out.println(Json.write(result));
    }

    private static long saturatingAdd(long left, long right) {
        return Long.MAX_VALUE - left < right ? Long.MAX_VALUE : left + right;
    }

    private static Map<String, String> parse(String[] args) {
        Map<String, String> out = new LinkedHashMap<>();
        for (int i = 0; i < args.length; i += 2) {
            if (!args[i].startsWith("--") || i + 1 == args.length) throw new IllegalArgumentException("arguments must be --name value pairs");
            out.put(args[i].substring(2), args[i + 1]);
        }
        return out;
    }

    private static String required(Map<String, String> values, String key) {
        String value = values.get(key);
        if (value == null || value.isBlank()) throw new IllegalArgumentException("missing --" + key);
        return value;
    }

    private static Instant optionalInstant(Map<String, String> values, String key) {
        String value = values.get(key);
        return value == null || value.isBlank() ? null : Instant.parse(value);
    }
}
