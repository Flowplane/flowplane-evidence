package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

class AssignmentSelectionTest {
    private static final ObjectMapper JSON = new ObjectMapper();

    @Test void acceptsRealAssignmentShapeWithoutTransportWhenExactIdentityMatches() throws Exception {
        GrpcObservationClient.Config config = config();
        var assignments = JSON.readTree("""
            [{
              "tenantId": "acme-corp",
              "runtimeId": "runtime-test",
              "mappingId": "mapping-test",
              "version": 7,
              "artifactId": "artifact-test",
              "artifactHash": "sha256:test",
              "name": "benchmark mapping"
            }]
            """);

        GrpcObservationClient.Assignment selected = GrpcObservationClient.selectAssignment(assignments, config);

        assertEquals("runtime-test", selected.runtimeId());
        assertEquals("mapping-test", selected.mappingId());
        assertEquals("artifact-test", selected.artifactId());
        assertEquals("sha256:test", selected.artifactHash());
        assertEquals("7", selected.mappingVersion());
    }

    @Test void rejectsNearMatchWithDifferentArtifactIdentity() throws Exception {
        var assignments = JSON.readTree("""
            [{
              "tenantId": "acme-corp",
              "runtimeId": "runtime-test",
              "mappingId": "mapping-test",
              "version": 7,
              "artifactId": "different-artifact",
              "artifactHash": "sha256:test"
            }]
            """);

        assertThrows(IllegalStateException.class,
            () -> GrpcObservationClient.selectAssignment(assignments, config()));
    }

    private static GrpcObservationClient.Config config() {
        return GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", "payloads.jsonl", "--run-dir", "results",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test",
            "--expected-mapping-id", "mapping-test", "--expected-artifact-id", "artifact-test",
            "--expected-artifact-hash", "sha256:test"
        });
    }
}
