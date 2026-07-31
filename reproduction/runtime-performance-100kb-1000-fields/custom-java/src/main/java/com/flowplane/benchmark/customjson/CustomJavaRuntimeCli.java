package com.flowplane.benchmark.customjson;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.header.Header;
import org.apache.kafka.common.header.Headers;
import org.apache.kafka.common.header.internals.RecordHeaders;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.common.serialization.ByteArraySerializer;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicReference;

public final class CustomJavaRuntimeCli {
    private static final JsonFactory JSON = JsonFactory.builder().build();

    private CustomJavaRuntimeCli() {}

    public static void main(String[] rawArgs) throws Exception {
        if (rawArgs.length == 0) usage();
        String command = rawArgs[0];
        Map<String, String> args = args(rawArgs, 1);
        verifyMapping(required(args, "mapping"));
        switch (command) {
            case "parity" -> parity(args);
            case "kafka" -> kafka(args);
            default -> usage();
        }
    }

    private static void parity(Map<String, String> args) throws Exception {
        Path requests = Path.of(required(args, "requests")).toAbsolutePath().normalize();
        Path responses = Path.of(required(args, "responses")).toAbsolutePath().normalize();
        HardMappingTransformer transformer = new HardMappingTransformer();
        Files.createDirectories(responses.getParent());
        try (BufferedReader reader = Files.newBufferedReader(requests, StandardCharsets.UTF_8);
             BufferedWriter writer = Files.newBufferedWriter(responses, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) continue;
                ParityRequest request = parseRequest(line);
                HardMappingTransformer.Result result = transformer.transform(
                        request.payload, context(request.headers));
                writeResponse(writer, request, result);
            }
        }
    }

    private static void kafka(Map<String, String> args) {
        String bootstrap = required(args, "bootstrap");
        String inputTopic = required(args, "input-topic");
        String outputTopic = required(args, "output-topic");
        String dlqTopic = required(args, "dlq-topic");
        String groupId = required(args, "group-id");
        long expected = Long.parseLong(required(args, "expected-records"));
        int maxPoll = Integer.parseInt(args.getOrDefault("max-poll-records", "500"));

        Properties consumerProperties = new Properties();
        consumerProperties.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        consumerProperties.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        consumerProperties.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class);
        consumerProperties.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class);
        consumerProperties.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        consumerProperties.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        consumerProperties.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, Integer.toString(maxPoll));
        consumerProperties.put(ConsumerConfig.FETCH_MIN_BYTES_CONFIG, args.getOrDefault("fetch-min-bytes", "1048576"));
        consumerProperties.put(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG, args.getOrDefault("fetch-max-wait-ms", "50"));

        Properties producerProperties = new Properties();
        producerProperties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        producerProperties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class);
        producerProperties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class);
        producerProperties.put(ProducerConfig.ACKS_CONFIG, "all");
        producerProperties.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        producerProperties.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, args.getOrDefault("compression", "none"));
        producerProperties.put(ProducerConfig.LINGER_MS_CONFIG, args.getOrDefault("linger-ms", "5"));
        producerProperties.put(ProducerConfig.BATCH_SIZE_CONFIG, args.getOrDefault("batch-size", "1048576"));
        producerProperties.put(ProducerConfig.BUFFER_MEMORY_CONFIG, args.getOrDefault("buffer-memory", "268435456"));
        producerProperties.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, args.getOrDefault("max-request-size", "2097152"));

        HardMappingTransformer transformer = new HardMappingTransformer();
        AtomicReference<Throwable> asyncFailure = new AtomicReference<>();
        long processed = 0;
        long output = 0;
        long dlq = 0;
        long transformNanos = 0;
        Instant start = Instant.now();
        try (KafkaConsumer<byte[], byte[]> consumer = new KafkaConsumer<>(consumerProperties);
             KafkaProducer<byte[], byte[]> producer = new KafkaProducer<>(producerProperties)) {
            consumer.subscribe(List.of(inputTopic));
            while (processed < expected) {
                Throwable failure = asyncFailure.get();
                if (failure != null) throw new IllegalStateException("Kafka produce failed", failure);
                ConsumerRecords<byte[], byte[]> records = consumer.poll(Duration.ofMillis(250));
                for (ConsumerRecord<byte[], byte[]> record : records) {
                    if (processed >= expected) break;
                    long before = System.nanoTime();
                    HardMappingTransformer.Result result =
                            transformer.transform(record.value(), context(record.headers()));
                    transformNanos += System.nanoTime() - before;
                    byte[] value;
                    String destination;
                    if (result.status() == HardMappingTransformer.Status.OUTPUT) {
                        value = result.output();
                        destination = outputTopic;
                        output++;
                    } else {
                        value = PolicyProjection.liveDlqEnvelope(
                                record.value(),
                                record.key(),
                                new PolicyProjection.Source(record.topic(), record.partition(), record.offset()),
                                result.fieldErrors());
                        destination = dlqTopic;
                        dlq++;
                    }
                    ProducerRecord<byte[], byte[]> produced = new ProducerRecord<>(
                            destination, null, record.timestamp(), record.key(), value, copyHeaders(record.headers()));
                    producer.send(produced, (metadata, exception) -> {
                        if (exception != null) asyncFailure.compareAndSet(null, exception);
                    });
                    processed++;
                }
            }
            producer.flush();
            Throwable failure = asyncFailure.get();
            if (failure != null) throw new IllegalStateException("Kafka produce failed", failure);
            consumer.commitSync();
        }
        Instant end = Instant.now();
        double seconds = Duration.between(start, end).toNanos() / 1_000_000_000.0;
        System.out.printf(
                "{\"schemaVersion\":1,\"runtime\":\"CUSTOM_JAVA_JSON\",\"mappingSha256\":\"%s\","
                        + "\"startedAt\":\"%s\",\"completedAt\":\"%s\",\"records\":%d,\"output\":%d,"
                        + "\"dlq\":%d,\"durationSeconds\":%.6f,\"recordsPerSecond\":%.3f,"
                        + "\"transformNanos\":%d,\"transformNanosPerRecord\":%.3f}%n",
                HardMappingTransformer.MAPPING_SHA256, start, end, processed, output, dlq, seconds,
                processed / seconds, transformNanos, processed == 0 ? 0 : (double) transformNanos / processed);
    }

    private static RecordHeaders copyHeaders(Headers source) {
        RecordHeaders copy = new RecordHeaders();
        for (Header h : source) copy.add(h.key(), h.value());
        return copy;
    }

    private static HardMappingTransformer.RecordContext context(Headers headers) {
        String tenant = lastHeader(headers, "tenant");
        String source = lastHeader(headers, "source");
        return new HardMappingTransformer.RecordContext(tenant, source);
    }

    private static HardMappingTransformer.RecordContext context(List<ParityHeader> headers) {
        String tenant = null;
        String source = null;
        for (ParityHeader h : headers) {
            String value = new String(h.value, StandardCharsets.UTF_8);
            if ("tenant".equals(h.key)) tenant = value;
            if ("source".equals(h.key)) source = value;
        }
        return new HardMappingTransformer.RecordContext(tenant, source);
    }

    private static String lastHeader(Headers headers, String key) {
        Header header = headers.lastHeader(key);
        return header == null || header.value() == null ? null
                : new String(header.value(), StandardCharsets.UTF_8);
    }

    private static ParityRequest parseRequest(String line) throws IOException {
        String recordId = null;
        String keyBase64 = "";
        byte[] payload = null;
        PolicyProjection.Source source = null;
        List<ParityHeader> headers = new ArrayList<>();
        try (JsonParser p = JSON.createParser(line)) {
            if (p.nextToken() != JsonToken.START_OBJECT) throw new IllegalArgumentException("request must be object");
            while (p.nextToken() != JsonToken.END_OBJECT) {
                String n = p.currentName();
                p.nextToken();
                switch (n) {
                    case "recordId" -> recordId = p.getValueAsString();
                    case "keyBase64" -> keyBase64 = p.getValueAsString();
                    case "payloadBase64" -> payload = Base64.getDecoder().decode(p.getValueAsString());
                    case "source" -> {
                        String topic = null;
                        int partition = 0;
                        long offset = 0;
                        while (p.nextToken() != JsonToken.END_OBJECT) {
                            String sn = p.currentName();
                            p.nextToken();
                            if ("topic".equals(sn)) topic = p.getValueAsString();
                            else if ("partition".equals(sn)) partition = p.getIntValue();
                            else if ("offset".equals(sn)) offset = p.getLongValue();
                            else p.skipChildren();
                        }
                        source = new PolicyProjection.Source(topic, partition, offset);
                    }
                    case "headers" -> {
                        while (p.nextToken() != JsonToken.END_ARRAY) {
                            String key = null;
                            byte[] value = null;
                            while (p.nextToken() != JsonToken.END_OBJECT) {
                                String hn = p.currentName();
                                p.nextToken();
                                if ("key".equals(hn)) key = p.getValueAsString();
                                else if ("valueBase64".equals(hn)) value = Base64.getDecoder().decode(p.getValueAsString());
                                else p.skipChildren();
                            }
                            headers.add(new ParityHeader(key, value == null ? new byte[0] : value));
                        }
                    }
                    default -> p.skipChildren();
                }
            }
        }
        if (recordId == null || payload == null) throw new IllegalArgumentException("recordId/payloadBase64 required");
        return new ParityRequest(recordId, keyBase64, payload, headers, source);
    }

    private static void writeResponse(BufferedWriter writer, ParityRequest request,
                                      HardMappingTransformer.Result result) throws IOException {
        java.io.StringWriter line = new java.io.StringWriter();
        try (JsonGenerator g = JSON.createGenerator(line)) {
            g.writeStartObject();
            g.writeStringField("recordId", request.recordId);
            g.writeStringField("status", result.status().name());
            g.writeStringField("keyBase64", request.keyBase64);
            writeHeaders(g, request.headers);
            writeSource(g, request.source);
            if (result.status() == HardMappingTransformer.Status.OUTPUT) {
                g.writeStringField("outputBase64", Base64.getEncoder().encodeToString(result.output()));
                g.writeArrayFieldStart("fieldErrors");
                g.writeEndArray();
                g.writeObjectFieldStart("http");
                g.writeNumberField("httpStatus", 200);
                g.writeStringField("resultHeader", "SUCCESS");
                g.writeNullField("errorEnvelope");
                g.writeEndObject();
                g.writeNullField("error");
                g.writeNullField("dlq");
            } else {
                List<HardMappingTransformer.MappingError> errors = result.fieldErrors();
                HardMappingTransformer.MappingError first = errors.getFirst();
                g.writeStringField("outputBase64", "");
                PolicyProjection.writeFieldErrors(g, errors, false);
                PolicyProjection.writeNormalizedHttp(g, errors, request.source);
                PolicyProjection.writeGrpcError(g, errors);
                PolicyProjection.writeGrpcDlq(g, request.recordId, errors);
            }
            g.writeEndObject();
        }
        writer.write(line.toString());
        writer.write('\n');
    }

    private static void writeHeaders(JsonGenerator g, List<ParityHeader> headers) throws IOException {
        g.writeArrayFieldStart("headers");
        for (ParityHeader header : headers) {
            g.writeStartObject();
            g.writeStringField("key", header.key);
            g.writeStringField("valueBase64", Base64.getEncoder().encodeToString(header.value));
            g.writeEndObject();
        }
        g.writeEndArray();
    }

    private static void writeSource(JsonGenerator g, PolicyProjection.Source source) throws IOException {
        PolicyProjection.writeSource(g, source);
    }

    private static void verifyMapping(String mappingPath) throws Exception {
        byte[] mapping = Files.readAllBytes(Path.of(mappingPath).toAbsolutePath().normalize());
        String actual = java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(mapping));
        if (!HardMappingTransformer.MAPPING_SHA256.equals(actual)) {
            throw new IllegalArgumentException("mapping SHA-256 mismatch: expected "
                    + HardMappingTransformer.MAPPING_SHA256 + ", got " + actual);
        }
    }

    private static Map<String, String> args(String[] values, int start) {
        Map<String, String> parsed = new HashMap<>();
        for (int i = start; i < values.length; i += 2) {
            if (!values[i].startsWith("--") || i + 1 == values.length) usage();
            parsed.put(values[i].substring(2), values[i + 1]);
        }
        return parsed;
    }

    private static String required(Map<String, String> args, String key) {
        String value = args.get(key);
        if (value == null || value.isBlank()) throw new IllegalArgumentException("--" + key + " is required");
        return value;
    }

    private static void usage() {
        throw new IllegalArgumentException("""
                Usage:
                  parity --mapping <dsl> --requests <jsonl> --responses <jsonl>
                  kafka --mapping <dsl> --bootstrap <host:port> --input-topic <topic>
                        --output-topic <topic> --dlq-topic <topic> --group-id <id>
                        --expected-records <count> [--max-poll-records <count> ...]
                """);
    }

    private record ParityHeader(String key, byte[] value) {}
    private record ParityRequest(String recordId, String keyBase64, byte[] payload,
                                 List<ParityHeader> headers, PolicyProjection.Source source) {}
}
