package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class ConfigTest {
    @Test void defaultsToTheObservational500kCampaign() {
        GrpcObservationClient.Config config = GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", Path.of("payloads.jsonl").toString(), "--run-dir", Path.of("results").toString(),
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test",
            "--expected-mapping-id", "mapping-test", "--expected-artifact-id", "artifact-test",
            "--expected-artifact-hash", "sha256:test"
        });
        assertEquals(500_000, config.recordCount());
        assertEquals(100, config.payloadVariants());
        assertEquals(102_400, config.payloadBytes());
        assertEquals(4, config.streams());
        assertEquals(128, config.maxInflightBatches());
    }

    @Test void rejectsAnInflightLimitSmallerThanStreamCount() {
        assertThrows(IllegalArgumentException.class, () -> GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", "payloads.jsonl", "--run-dir", "results", "--expected-artifact-hash", "sha256:test",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test", "--expected-mapping-id", "mapping-test",
            "--expected-artifact-id", "artifact-test",
            "--streams", "8", "--max-inflight-batches", "4"
        }));
    }

    @Test void refusesToOverwriteExistingMeasuredEvidence(@TempDir Path runDirectory) throws Exception {
        Files.createFile(runDirectory.resolve("grpc-client.jfr"));
        GrpcObservationClient.Config config = GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", "payloads.jsonl", "--run-dir", runDirectory.toString(),
            "--expected-artifact-hash", "sha256:test", "--campaign-id", "grpc-test",
            "--expected-runtime-id", "runtime-test", "--expected-mapping-id", "mapping-test",
            "--expected-artifact-id", "artifact-test"
        });

        assertThrows(IllegalStateException.class, () -> GrpcObservationClient.assertFreshOutputDirectory(config));
    }

    @Test void refusesToOverwriteCustomJfrOutsideTheRunDirectory(@TempDir Path temporary) throws Exception {
        Path runDirectory = Files.createDirectory(temporary.resolve("run"));
        Path customJfr = Files.createFile(temporary.resolve("custom-client.jfr"));
        GrpcObservationClient.Config config = GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", "payloads.jsonl", "--run-dir", runDirectory.toString(),
            "--jfr-file", customJfr.toString(), "--expected-artifact-hash", "sha256:test",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test",
            "--expected-mapping-id", "mapping-test", "--expected-artifact-id", "artifact-test"
        });

        assertThrows(IllegalStateException.class, () -> GrpcObservationClient.assertFreshOutputDirectory(config));
    }
}
