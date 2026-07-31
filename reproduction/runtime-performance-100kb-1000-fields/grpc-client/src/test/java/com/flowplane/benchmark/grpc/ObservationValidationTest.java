package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.nio.file.Path;
import java.time.Instant;
import java.util.Map;
import org.junit.jupiter.api.Test;

class ObservationValidationTest {
    @Test void acceptsCompleteAccountedObservation() {
        assertDoesNotThrow(() -> observation(true, 10, 2, 10, 2, 9, 1, 0, 0, null).requireComplete());
    }

    @Test void rejectsIncompleteDrain() {
        assertThrows(IllegalStateException.class,
            () -> observation(false, 10, 2, 10, 2, 10, 0, 0, 0, null).requireComplete());
    }

    @Test void rejectsRpcError() {
        assertThrows(IllegalStateException.class,
            () -> observation(true, 10, 2, 10, 2, 10, 0, 0, 0, "stream failed").requireComplete());
    }

    @Test void rejectsShortResponseAccounting() {
        assertThrows(IllegalStateException.class,
            () -> observation(true, 10, 2, 9, 2, 9, 0, 0, 0, null).requireComplete());
    }

    @Test void rejectsUnknownOrOutstandingBatchAccounting() {
        assertThrows(IllegalStateException.class,
            () -> observation(true, 10, 2, 10, 1, 10, 0, 0, 1, null).requireComplete());
    }

    @Test void rejectsStatusTotalMismatch() {
        assertThrows(IllegalStateException.class,
            () -> observation(true, 10, 2, 10, 2, 9, 0, 0, 0, null).requireComplete());
    }

    private static GrpcObservationClient.Observation observation(
            boolean drained, long sentRecords, long sentBatches, long responseRecords, long responseBatches,
            long ok, long dlq, long failed, int outstanding, String rpcError) {
        GrpcObservationClient.Config config = GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", Path.of("payloads.jsonl").toString(), "--run-dir", Path.of("results").toString(),
            "--record-count", "10", "--batch-size", "5", "--campaign-id", "grpc-test",
            "--expected-runtime-id", "runtime-test", "--expected-mapping-id", "mapping-test",
            "--expected-artifact-id", "artifact-test", "--expected-artifact-hash", "sha256:test"
        });
        Instant now = Instant.parse("2026-07-31T00:00:00Z");
        return new GrpcObservationClient.Observation(config, now, now.plusSeconds(1), drained,
            sentRecords, sentBatches, responseRecords, responseBatches, ok, dlq, failed, 1_000,
            outstanding, 2, rpcError, Map.of(), Map.of());
    }
}
