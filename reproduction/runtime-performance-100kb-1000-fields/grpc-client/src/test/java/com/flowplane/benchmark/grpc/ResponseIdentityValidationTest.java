package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.flowplane.runtime.v1.TransformBatchResponse;
import com.flowplane.runtime.v1.TransformResult;
import com.flowplane.runtime.v1.TransformStatus;
import com.flowplane.runtime.v1.TransformStreamResponse;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ResponseIdentityValidationTest {
    @TempDir Path temporary;

    @Test void rejectsWrongPerBatchResultCount() throws Exception {
        try (GrpcObservationClient.SampleWriter writer = writer()) {
            GrpcObservationClient.RunState state = state(writer, 2);
            register(state, "batch-0", 0, 2);

            state.accept(response("batch-0", "grpc-record-0"), 0);

            assertTrue(state.stop.get());
            assertTrue(state.firstError.get().contains("returned 1 records; expected 2"));
            assertEquals(0L, state.responseRecords.sum());
        }
    }

    @Test void rejectsDuplicateRecordIdentityEvenWhenCountMatches() throws Exception {
        try (GrpcObservationClient.SampleWriter writer = writer()) {
            GrpcObservationClient.RunState state = state(writer, 2);
            register(state, "batch-0", 0, 2);

            state.accept(response("batch-0", "grpc-record-0", "grpc-record-0"), 0);

            assertTrue(state.stop.get());
            assertTrue(state.firstError.get().contains("duplicate record id grpc-record-0"));
            assertEquals(0L, state.responseRecords.sum());
        }
    }

    @Test void rejectsRecordIdentityFromAnotherBatch() throws Exception {
        try (GrpcObservationClient.SampleWriter writer = writer()) {
            GrpcObservationClient.RunState state = state(writer, 2);
            register(state, "batch-0", 10, 2);

            state.accept(response("batch-0", "grpc-record-10", "grpc-record-12"), 0);

            assertTrue(state.stop.get());
            assertTrue(state.firstError.get().contains("out-of-range record id grpc-record-12"));
        }
    }

    @Test void acceptsCompleteOutOfOrderIdentitySet() throws Exception {
        try (GrpcObservationClient.SampleWriter writer = writer()) {
            GrpcObservationClient.RunState state = state(writer, 2);
            register(state, "batch-0", 10, 2);

            state.accept(response("batch-0", "grpc-record-11", "grpc-record-10"), 0);

            assertFalse(state.stop.get());
            assertEquals(2L, state.responseRecords.sum());
            assertEquals(2L, state.ok.sum());
        }
    }

    @Test void recordsPeakWhenFlightsAreRegisteredNotWhenResponsesArrive() throws Exception {
        try (GrpcObservationClient.SampleWriter writer = writer()) {
            GrpcObservationClient.RunState state = state(writer, 3);
            register(state, "batch-0", 0, 1);
            register(state, "batch-1", 1, 1);
            register(state, "batch-2", 2, 1);

            assertEquals(3, state.activeInflight.get());
            assertEquals(3, state.peakInflight.get());

            state.accept(response("batch-1", "grpc-record-1"), 0);
            assertEquals(2, state.activeInflight.get());
            assertEquals(3, state.peakInflight.get());
        }
    }

    private GrpcObservationClient.SampleWriter writer() throws Exception {
        return new GrpcObservationClient.SampleWriter(temporary.resolve("samples-" + System.nanoTime() + ".jsonl"), 100);
    }

    private GrpcObservationClient.RunState state(GrpcObservationClient.SampleWriter writer, int batches) {
        return new GrpcObservationClient.RunState(config(), batches, writer);
    }

    private void register(GrpcObservationClient.RunState state, String batchId, int first, int count) {
        state.inflight.acquireUninterruptibly();
        state.registerFlight(batchId, new GrpcObservationClient.Flight(System.nanoTime(), first, count));
    }

    private GrpcObservationClient.Config config() {
        return GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", temporary.resolve("payloads.jsonl").toString(),
            "--run-dir", temporary.toString(), "--record-count", "20", "--batch-size", "2",
            "--streams", "1", "--max-inflight-batches", "10",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test",
            "--expected-mapping-id", "mapping-test", "--expected-artifact-id", "artifact-test",
            "--expected-artifact-hash", "sha256:test"
        });
    }

    private static TransformStreamResponse response(String batchId, String... recordIds) {
        TransformBatchResponse.Builder batch = TransformBatchResponse.newBuilder();
        for (String recordId : recordIds) {
            batch.addResults(TransformResult.newBuilder()
                .setRecordId(recordId).setStatus(TransformStatus.OK));
        }
        return TransformStreamResponse.newBuilder().setBatchId(batchId).setBatch(batch).build();
    }
}
