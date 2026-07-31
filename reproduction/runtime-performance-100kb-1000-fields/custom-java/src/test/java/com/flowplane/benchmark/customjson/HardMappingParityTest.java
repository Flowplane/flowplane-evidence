package com.flowplane.benchmark.customjson;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;

final class HardMappingParityTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Path ROOT = Path.of("..").toAbsolutePath().normalize();

    @Test
    void exactMappingIdentityAndAllOneHundredValidOutputsMatchByteForByte() throws Exception {
        Path mapping = ROOT.resolve("mapping/mapping.dsl");
        String mappingHash = java.util.HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(mapping)));
        assertEquals(HardMappingTransformer.MAPPING_SHA256, mappingHash);

        List<String> payloads = Files.readAllLines(
                ROOT.resolve("workload/generated/valid-payloads-100kb.jsonl"), StandardCharsets.UTF_8);
        List<String> oracle = Files.readAllLines(
                ROOT.resolve("custom-java/oracle/grpc-hard-valid-flowplane.jsonl"), StandardCharsets.UTF_8);
        assertEquals(100, payloads.size());
        assertEquals(100, oracle.size());

        HardMappingTransformer transformer = new HardMappingTransformer();
        for (int i = 0; i < 100; i++) {
            byte[] input = payloads.get(i).getBytes(StandardCharsets.UTF_8);
            assertEquals(102_400, input.length, "input bytes at variant " + i);
            JsonNode evidence = JSON.readTree(oracle.get(i));
            byte[] expected = Base64.getDecoder().decode(evidence.path("outputBase64").asText());
            HardMappingTransformer.Result result =
                    transformer.transform(input, HardMappingTransformer.RecordContext.EMPTY);
            assertEquals(HardMappingTransformer.Status.OUTPUT, result.status(),
                    "variant " + i + " errors=" + result.fieldErrors());
            assertArrayEquals(expected, result.output(), "variant " + i + " " + firstDifference(expected, result.output()));
        }
    }

    private static String firstDifference(byte[] expected, byte[] actual) {
        int n = Math.min(expected.length, actual.length);
        int at = 0;
        while (at < n && expected[at] == actual[at]) at++;
        int from = Math.max(0, at - 80);
        int expectedTo = Math.min(expected.length, at + 160);
        int actualTo = Math.min(actual.length, at + 160);
        return "firstDifference=" + at
                + " expected=" + new String(expected, from, expectedTo - from, StandardCharsets.UTF_8)
                + " actual=" + new String(actual, from, actualTo - from, StandardCharsets.UTF_8);
    }

    @Test
    void invalidRequiredFieldRoutesToDlqWithoutThrowing() {
        byte[] invalid = "{\"run\":{},\"wide\":{}}".getBytes(StandardCharsets.UTF_8);
        HardMappingTransformer.Result result =
                new HardMappingTransformer().transform(invalid, HardMappingTransformer.RecordContext.EMPTY);
        assertEquals(HardMappingTransformer.Status.DLQ, result.status());
        assertEquals("VALIDATION_FAILURE", result.fieldErrors().getFirst().code());
    }
}
