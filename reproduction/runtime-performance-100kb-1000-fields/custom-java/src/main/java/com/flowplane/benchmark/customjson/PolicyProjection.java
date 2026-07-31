package com.flowplane.benchmark.customjson;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonGenerator;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

/**
 * One policy projection shared by offline parity and the live Kafka DLQ path.
 *
 * <p>Valid records never enter this class. Allocation in this failure-only path
 * is deliberately outside the measured valid population.</p>
 */
final class PolicyProjection {
    static final String TENANT_ID = "benchmark-tenant";
    static final String RUNTIME_ID = "custom-java-zero-copy";
    static final String MAPPING_ID = "grpc-hard-complexity-v1";
    static final String MAPPING_VERSION = "v1";
    static final String ARTIFACT_HASH = "sha256:" + HardMappingTransformer.MAPPING_SHA256;
    private static final JsonFactory JSON = JsonFactory.builder().build();
    private static final int SNIPPET_LIMIT = 4096;

    private PolicyProjection() {}

    static void writeNormalizedHttp(JsonGenerator generator,
                                    List<HardMappingTransformer.MappingError> errors,
                                    Source source) throws IOException {
        HardMappingTransformer.MappingError first = first(errors);
        generator.writeObjectFieldStart("http");
        generator.writeNumberField("httpStatus", 422);
        generator.writeStringField("resultHeader", "ERROR");
        generator.writeObjectFieldStart("errorEnvelope");
        generator.writeStringField("schemaVersion", "flowplane.runtime.error.v1");
        generator.writeStringField("type", "com.flowplane.runtime.error");
        generator.writeStringField("tenantId", TENANT_ID);
        generator.writeObjectFieldStart("runtime");
        generator.writeStringField("id", RUNTIME_ID);
        generator.writeStringField("type", "HTTP");
        generator.writeEndObject();
        generator.writeObjectFieldStart("artifact");
        generator.writeStringField("mappingId", MAPPING_ID);
        generator.writeStringField("artifactVersion", MAPPING_VERSION);
        generator.writeStringField("artifactHash", ARTIFACT_HASH);
        generator.writeEndObject();
        writeSource(generator, source);
        writeGroupedError(generator, errors);
        writeErrors(generator, errors);
        generator.writeObjectFieldStart("policy");
        generator.writeStringField("action", "ROUTE_TO_DLQ");
        generator.writeStringField("format", "ENVELOPE");
        generator.writeEndObject();
        generator.writeObjectFieldStart("generatedFields");
        generator.writeStringField("errorIdPattern", "^err-[0-9a-f-]{36}$");
        generator.writeStringField("timestampFormat", "ISO-8601");
        generator.writeEndObject();
        generator.writeEndObject();
        generator.writeEndObject();
    }

    static void writeGrpcError(JsonGenerator generator,
                               List<HardMappingTransformer.MappingError> errors) throws IOException {
        HardMappingTransformer.MappingError first = first(errors);
        boolean invalidPayload = "INVALID_PAYLOAD".equals(first.code());
        generator.writeObjectFieldStart("error");
        generator.writeStringField("code", invalidPayload ? "INVALID_PAYLOAD" : "VALIDATION_FAILED");
        generator.writeStringField("message", first.message());
        if (invalidPayload) generator.writeNullField("fieldPath");
        else generator.writeStringField("fieldPath", first.field());
        generator.writeStringField("stage", invalidPayload ? "INPUT_PARSE" : "CORE_MAPPING");
        generator.writeBooleanField("retryable", false);
        generator.writeEndObject();
    }

    static void writeGrpcDlq(JsonGenerator generator,
                             String recordId,
                             List<HardMappingTransformer.MappingError> errors) throws IOException {
        boolean invalidPayload = "INVALID_PAYLOAD".equals(first(errors).code());
        generator.writeObjectFieldStart("dlq");
        generator.writeStringField("reason", invalidPayload ? "INVALID_PAYLOAD" : "VALIDATION_FAILED");
        generator.writeStringField("tenantId", TENANT_ID);
        generator.writeStringField("runtimeId", RUNTIME_ID);
        generator.writeStringField("mappingId", MAPPING_ID);
        generator.writeStringField("mappingVersion", MAPPING_VERSION);
        generator.writeStringField("artifactHash", ARTIFACT_HASH);
        generator.writeStringField("originalRecordId", recordId);
        generator.writeObjectFieldStart("metadata");
        generator.writeStringField("stage", invalidPayload ? "INPUT_PARSE" : "CORE_MAPPING");
        generator.writeEndObject();
        generator.writeEndObject();
    }

    static byte[] liveDlqEnvelope(byte[] payload,
                                  byte[] key,
                                  Source source,
                                  List<HardMappingTransformer.MappingError> errors) {
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream(SNIPPET_LIMIT + 2048);
            String errorId = "err-" + UUID.randomUUID();
            String timestamp = Instant.now().toString();
            String payloadSnippet = redact(new String(payload, StandardCharsets.UTF_8));
            if (payloadSnippet.length() > SNIPPET_LIMIT) {
                payloadSnippet = payloadSnippet.substring(0, SNIPPET_LIMIT);
            }
            try (JsonGenerator generator = JSON.createGenerator(bytes)) {
                generator.writeStartObject();
                generator.writeStringField("schemaVersion", "flowplane.runtime.error.v1");
                generator.writeStringField("type", "com.flowplane.runtime.error");
                generator.writeStringField("errorId", errorId);
                generator.writeStringField("timestamp", timestamp);
                generator.writeStringField("tenantId", TENANT_ID);
                generator.writeObjectFieldStart("runtime");
                generator.writeStringField("id", RUNTIME_ID);
                generator.writeStringField("name", "Custom Java JSON Baseline");
                generator.writeStringField("type", "CUSTOM_JAVA_JSON");
                generator.writeEndObject();
                generator.writeObjectFieldStart("artifact");
                generator.writeStringField("mappingId", MAPPING_ID);
                generator.writeStringField("mappingName", "grpc-hard-complexity-v1");
                generator.writeStringField("artifactId", "custom-java-json-runtime");
                generator.writeStringField("artifactVersion", MAPPING_VERSION);
                generator.writeStringField("artifactHash", ARTIFACT_HASH);
                generator.writeEndObject();
                generator.writeObjectFieldStart("source");
                generator.writeStringField("topic", source.topic());
                generator.writeNumberField("partition", source.partition());
                generator.writeNumberField("offset", source.offset());
                generator.writeStringField("key", Base64.getEncoder().encodeToString(
                    key == null ? new byte[0] : key));
                generator.writeEndObject();
                writeGroupedError(generator, errors);
                writeErrors(generator, errors);
                generator.writeObjectFieldStart("policy");
                generator.writeStringField("action", "ROUTE_TO_DLQ");
                generator.writeStringField("format", "ENVELOPE");
                generator.writeStringField("topicTemplate", "${inputTopic}.flowplane.dlq");
                generator.writeNumberField("maxPayloadBytes", SNIPPET_LIMIT);
                generator.writeEndObject();
                generator.writeObjectFieldStart("payload");
                generator.writeStringField("snippet", payloadSnippet);
                generator.writeBooleanField("redacted", true);
                generator.writeBooleanField("fullPayloadIncluded", false);
                generator.writeEndObject();
                generator.writeNullField("correlationId");
                generator.writeNullField("traceId");
                generator.writeObjectFieldStart("attributes");
                generator.writeStringField("category", "TRANSFORMATION");
                generator.writeBooleanField("retryable", false);
                generator.writeObjectFieldStart("errorOutput");
                generator.writeStringField("action", "ROUTE_TO_DLQ");
                generator.writeStringField("format", "ENVELOPE");
                generator.writeStringField("topicTemplate", "${inputTopic}.flowplane.dlq");
                generator.writeNumberField("maxPayloadBytes", SNIPPET_LIMIT);
                generator.writeEndObject();
                generator.writeBooleanField("payloadSnippetRedacted", true);
                writeErrors(generator, errors);
                generator.writeEndObject();
                generator.writeEndObject();
            }
            return bytes.toByteArray();
        } catch (IOException exception) {
            throw new IllegalStateException("Unable to serialize live DLQ envelope", exception);
        }
    }

    static void writeSource(JsonGenerator generator, Source source) throws IOException {
        generator.writeObjectFieldStart("source");
        generator.writeStringField("topic", source.topic());
        generator.writeNumberField("partition", source.partition());
        generator.writeNumberField("offset", source.offset());
        generator.writeEndObject();
    }

    static void writeFieldErrors(JsonGenerator generator,
                                 List<HardMappingTransformer.MappingError> errors,
                                 boolean includePath) throws IOException {
        generator.writeArrayFieldStart("fieldErrors");
        for (HardMappingTransformer.MappingError error : errors) {
            writeFieldError(generator, error, includePath);
        }
        generator.writeEndArray();
    }

    private static void writeGroupedError(JsonGenerator generator,
                                          List<HardMappingTransformer.MappingError> errors) throws IOException {
        HardMappingTransformer.MappingError first = first(errors);
        boolean invalidPayload = "INVALID_PAYLOAD".equals(first.code());
        generator.writeObjectFieldStart("error");
        generator.writeStringField("field", first.field());
        generator.writeStringField("path", invalidPayload ? "$" : first.field());
        generator.writeStringField("code", errors.size() == 1 ? first.code() : "MULTIPLE_FIELD_ERRORS");
        generator.writeStringField("severity", "ERROR");
        generator.writeStringField("message", errors.size() == 1 ? first.message()
            : errors.size() + " field errors occurred in one source record.");
        generator.writeStringField("category", "TRANSFORMATION");
        generator.writeBooleanField("retryable", false);
        generator.writeEndObject();
    }

    private static void writeErrors(JsonGenerator generator,
                                    List<HardMappingTransformer.MappingError> errors) throws IOException {
        generator.writeArrayFieldStart("errors");
        for (HardMappingTransformer.MappingError error : errors) {
            writeFieldError(generator, error, true);
        }
        generator.writeEndArray();
    }

    private static void writeFieldError(JsonGenerator generator,
                                        HardMappingTransformer.MappingError error,
                                        boolean includePath) throws IOException {
        generator.writeStartObject();
        generator.writeStringField("field", error.field());
        if (includePath) {
            generator.writeStringField(
                "path", "INVALID_PAYLOAD".equals(error.code()) ? "$" : error.field());
        }
        generator.writeStringField("code", error.code());
        generator.writeStringField("message", error.message());
        generator.writeEndObject();
    }

    private static HardMappingTransformer.MappingError first(
        List<HardMappingTransformer.MappingError> errors) {
        if (errors == null || errors.isEmpty()) {
            throw new IllegalArgumentException("DLQ projection requires at least one field error");
        }
        return errors.getFirst();
    }

    private static String redact(String value) {
        return value
            .replaceAll(
                "(?i)(\"?(pan|cardNumber|card_number|ssn|password|secret|token)\"?\\s*[:=]\\s*\")([^\"]+)(\")",
                "$1***REDACTED***$4")
            .replaceAll("\\b\\d{12,19}\\b", "***REDACTED_NUMBER***");
    }

    record Source(String topic, int partition, long offset) {}
}
