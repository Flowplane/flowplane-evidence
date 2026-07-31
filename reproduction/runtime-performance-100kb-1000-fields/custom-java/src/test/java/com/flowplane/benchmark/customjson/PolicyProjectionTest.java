package com.flowplane.benchmark.customjson;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PolicyProjectionTest {
    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    void liveKafkaDlqUsesFullSharedPolicyEnvelopeAndAllOrderedErrors() throws Exception {
        List<HardMappingTransformer.MappingError> errors = List.of(
            new HardMappingTransformer.MappingError(
                "orderAmountDouble", "TYPE_CONVERSION_FAILED",
                "Failed to cast value to double (invalid_number)"),
            new HardMappingTransformer.MappingError(
                "amountRounded", "TYPE_CONVERSION_FAILED",
                "Failed to cast value to decimal (invalid_number)"),
            new HardMappingTransformer.MappingError(
                "functionRound", "TYPE_CONVERSION_FAILED",
                "Failed to cast value to target type (invalid_number)"),
            new HardMappingTransformer.MappingError(
                "decimalTruncated", "TYPE_CONVERSION_FAILED",
                "Failed to cast value to decimal (invalid_number)")
        );
        byte[] payload = """
            {"customer":{"ssn":"123-45-6789"},"token":"do-not-emit","safe":"visible"}
            """.strip().getBytes(StandardCharsets.UTF_8);

        byte[] envelope = PolicyProjection.liveDlqEnvelope(
            payload,
            new byte[] {0, 1, (byte) 0xff},
            new PolicyProjection.Source("benchmark-input", 2, 42L),
            errors
        );
        JsonNode body = JSON.readTree(envelope);

        assertEquals("flowplane.runtime.error.v1", body.path("schemaVersion").asText());
        assertTrue(body.path("errorId").asText().matches("^err-[0-9a-f-]{36}$"));
        Instant.parse(body.path("timestamp").asText());
        assertEquals("MULTIPLE_FIELD_ERRORS", body.path("error").path("code").asText());
        assertEquals("4 field errors occurred in one source record.", body.path("error").path("message").asText());
        assertEquals(4, body.path("errors").size());
        assertEquals("orderAmountDouble", body.path("errors").get(0).path("field").asText());
        assertEquals("decimalTruncated", body.path("errors").get(3).path("field").asText());
        assertEquals("ROUTE_TO_DLQ", body.path("policy").path("action").asText());
        assertEquals("benchmark-input", body.path("source").path("topic").asText());
        assertEquals(2, body.path("source").path("partition").asInt());
        assertEquals(42L, body.path("source").path("offset").asLong());
        assertEquals("AAH/", body.path("source").path("key").asText());
        assertTrue(body.path("payload").path("redacted").asBoolean());
        assertFalse(body.path("payload").path("fullPayloadIncluded").asBoolean());
        assertTrue(body.path("payload").path("snippet").asText().contains("***REDACTED***"));
        assertFalse(body.path("payload").path("snippet").asText().contains("123-45-6789"));
        assertFalse(body.path("payload").path("snippet").asText().contains("do-not-emit"));
        assertEquals(4, body.path("attributes").path("errors").size());
    }

    @Test
    void malformedJsonUsesInputParsePolicyProjection() throws Exception {
        Path root = Path.of("..").toAbsolutePath().normalize();
        byte[] payload = Files.readAllLines(
            root.resolve("workload/generated/valid-payloads-100kb.jsonl"),
            StandardCharsets.UTF_8
        ).getFirst().getBytes(StandardCharsets.UTF_8);
        payload[0] = '!';

        HardMappingTransformer.Result result =
            new HardMappingTransformer().transform(payload, HardMappingTransformer.RecordContext.EMPTY);

        assertEquals(HardMappingTransformer.Status.DLQ, result.status());
        assertEquals(1, result.fieldErrors().size());
        assertEquals("<record>", result.fieldErrors().getFirst().field());
        assertEquals("INVALID_PAYLOAD", result.fieldErrors().getFirst().code());
        assertTrue(result.fieldErrors().getFirst().message().startsWith("Invalid payload JSON: "));
    }
}
