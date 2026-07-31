package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertTrue;

import com.flowplane.runtime.v1.DlqEnvelope;
import com.flowplane.runtime.v1.TransformError;
import com.flowplane.runtime.v1.TransformResult;
import com.flowplane.runtime.v1.TransformStatus;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ParityEvidenceWriterTest {
    @TempDir Path temporary;

    @Test
    void recordsDetailedErrorAndDlqPolicyEvidence() throws Exception {
        Path evidence = temporary.resolve("policy-evidence.jsonl");
        TransformResult result = TransformResult.newBuilder()
            .setRecordId("invalid-17")
            .setStatus(TransformStatus.DLQ)
            .putHeaders("policy", "route-to-dlq")
            .setError(TransformError.newBuilder()
                .setCode("TYPE_MISMATCH")
                .setMessage("order.amount must be decimal")
                .setFieldPath("$.order.amount")
                .setStage("TRANSFORM")
                .setRetryable(false))
            .setDlq(DlqEnvelope.newBuilder()
                .setReason("TYPE_MISMATCH")
                .setTenantId("benchmark")
                .setRuntimeId("grpc-hard")
                .setMappingId("grpc-hard-complexity")
                .setMappingVersion("1")
                .setArtifactHash("sha256:test")
                .setOriginalRecordId("invalid-17")
                .putMetadata("policy", "ROUTE_TO_DLQ"))
            .build();

        try (GrpcObservationClient.ParityWriter writer = new GrpcObservationClient.ParityWriter(evidence)) {
            writer.write("batch-policy-1", 2, result);
        }

        String line = Files.readString(evidence);
        assertTrue(line.contains("\"status\":\"DLQ\""));
        assertTrue(line.contains("\"code\":\"TYPE_MISMATCH\""));
        assertTrue(line.contains("\"fieldPath\":\"$.order.amount\""));
        assertTrue(line.contains("\"reason\":\"TYPE_MISMATCH\""));
        assertTrue(line.contains("\"originalRecordId\":\"invalid-17\""));
        assertTrue(line.contains("\"policy\":\"ROUTE_TO_DLQ\""));
    }
}
