package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import com.flowplane.runtime.v1.TransformBatchResponse;
import com.flowplane.runtime.v1.TransformResult;
import com.flowplane.runtime.v1.TransformStatus;
import com.flowplane.runtime.v1.TransformStreamResponse;
import com.google.protobuf.ByteString;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ResponseDisposalTest {
    @TempDir Path temporary;

    @Test void removesInflightResponseAndWritesOnlyBoundedDigestMetadata() throws Exception {
        GrpcObservationClient.Config config = GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", temporary.resolve("payloads.jsonl").toString(),
            "--run-dir", temporary.toString(), "--record-count", "1", "--batch-size", "1",
            "--streams", "1", "--max-inflight-batches", "1", "--expected-artifact-hash", "sha256:test",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test", "--expected-mapping-id", "mapping-test",
            "--expected-artifact-id", "artifact-test"
        });
        Path samples = temporary.resolve("samples.jsonl");
        try (GrpcObservationClient.SampleWriter writer = new GrpcObservationClient.SampleWriter(samples, 100)) {
            GrpcObservationClient.RunState state = new GrpcObservationClient.RunState(config, 1, writer);
            state.inflight.acquire();
            state.registerFlight("batch-0", new GrpcObservationClient.Flight(System.nanoTime(), 0, 1));
            ByteString transformed = ByteString.copyFromUtf8("sensitive-transformed-value");
            TransformStreamResponse response = TransformStreamResponse.newBuilder()
                .setBatchId("batch-0")
                .setBatch(TransformBatchResponse.newBuilder().addResults(TransformResult.newBuilder()
                    .setRecordId("grpc-record-0").setStatus(TransformStatus.OK).setOutput(transformed)))
                .build();
            state.accept(response, 0);
            assertTrue(state.pending.isEmpty());
            assertEquals(0, state.responses.getCount());
            assertEquals(1L, state.ok.sum());
        }
        String sample = Files.readString(samples);
        assertTrue(sample.contains("outputSha256"));
        assertFalse(sample.contains("sensitive-transformed-value"));
    }
}
