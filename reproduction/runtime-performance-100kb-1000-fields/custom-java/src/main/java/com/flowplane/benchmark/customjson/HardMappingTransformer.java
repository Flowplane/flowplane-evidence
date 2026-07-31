package com.flowplane.benchmark.customjson;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.JsonToken;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.ArrayList;
import java.util.Locale;

/**
 * Benchmark-only implementation of grpc-hard-complexity-v1.
 *
 * <p>The implementation deliberately has no dependency on FlowPlane. It parses tokens
 * incrementally, retains only the small core context, and emits each wide output field
 * directly from Jackson's token character buffer.</p>
 */
public final class HardMappingTransformer {
    public static final String MAPPING_SHA256 =
            "007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31";
    public static final int OUTPUT_FIELD_COUNT = 1000;
    public static final int WIDE_FIELD_COUNT = 923;

    private static final JsonFactory JSON = JsonFactory.builder().build();
    private static final byte[] HEX = "0123456789abcdef".getBytes(StandardCharsets.US_ASCII);
    private static final String[] SOURCE_WIDE_NAMES = fieldNames("field", 1000);
    private static final String[] TARGET_WIDE_NAMES = fieldNames("wideField", WIDE_FIELD_COUNT);

    public Result transform(byte[] payload, RecordContext recordContext) {
        Core c = new Core();
        // This field follows $.wide in the fixed corpus order. Read its small ASCII
        // scalar directly so wide fields can still be emitted in one streaming pass.
        c.mappingSchemaVersion = trailingAsciiString(payload, "\"mappingSchemaVersion\":\"");
        Utf8Writer out = new Utf8Writer(48_000);
        try (JsonParser p = JSON.createParser(payload)) {
            require(p.nextToken() == JsonToken.START_OBJECT, "root must be an object");
            boolean wroteCore = false;
            while (p.nextToken() != JsonToken.END_OBJECT) {
                require(p.currentToken() == JsonToken.FIELD_NAME, "root field name expected");
                String section = p.currentName();
                JsonToken value = p.nextToken();
                switch (section) {
                    case "run" -> readRun(p, c);
                    case "event" -> readEvent(p, c);
                    case "tenant" -> readTenant(p, c);
                    case "order" -> readOrder(p, c);
                    case "customer" -> readCustomer(p, c);
                    case "metrics" -> readMetrics(p, c);
                    case "signals" -> readSignals(p, c);
                    case "singleSignals" -> readSingleSignals(p, c);
                    case "packet" -> readPacket(p, c);
                    case "benchmark" -> readBenchmark(p, c);
                    case "wide" -> {
                        require(value == JsonToken.START_OBJECT, "wide must be an object");
                        List<MappingError> errors = policyErrors(c);
                        if (!errors.isEmpty()) throw new MappingException(errors);
                        out.beginObject();
                        writeCore(out, c, recordContext == null ? RecordContext.EMPTY : recordContext);
                        writeWide(p, out, c);
                        wroteCore = true;
                    }
                    default -> p.skipChildren();
                }
            }
            require(wroteCore, "required object $.wide is missing");
            out.endObject();
            return Result.output(out.toByteArray());
        } catch (IOException | RuntimeException e) {
            if (e instanceof MappingException me && me.errors != null) return Result.dlq(me.errors);
            if (e instanceof JsonProcessingException json) {
                return Result.dlq(List.of(new MappingError(
                    "<record>",
                    "INVALID_PAYLOAD",
                    "Invalid payload JSON: " + json.getOriginalMessage())));
            }
            String code = e instanceof MappingException me ? me.code : "TRANSFORMATION_ERROR";
            return Result.dlq(List.of(new MappingError("$", code, safeMessage(e))));
        }
    }

    private static void readRun(JsonParser p, Core c) throws IOException {
        requireObject(p, "run");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "campaignId" -> c.campaignId = p.getValueAsString();
                case "sequence" -> c.sequence = p.getLongValue();
                default -> p.skipChildren();
            }
        }
    }

    private static void readEvent(JsonParser p, Core c) throws IOException {
        requireObject(p, "event");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "id" -> c.eventId = p.getValueAsString();
                case "type" -> c.eventType = p.getValueAsString();
                case "ts" -> c.eventTimestamp = p.getValueAsString();
                case "trace" -> c.trace = p.getValueAsString();
                default -> p.skipChildren();
            }
        }
    }

    private static void readTenant(JsonParser p, Core c) throws IOException {
        requireObject(p, "tenant");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            if ("region".equals(n)) c.region = p.getValueAsString();
            else p.skipChildren();
        }
    }

    private static void readOrder(JsonParser p, Core c) throws IOException {
        requireObject(p, "order");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "id" -> c.orderId = p.getValueAsString();
                case "status" -> c.orderStatus = p.getValueAsString();
                case "amount" -> c.amount = p.getValueAsString();
                case "currency" -> c.currency = p.getValueAsString();
                default -> p.skipChildren();
            }
        }
    }

    private static void readCustomer(JsonParser p, Core c) throws IOException {
        requireObject(p, "customer");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "id" -> c.customerId = p.getValueAsString();
                case "tier" -> c.tier = p.getValueAsString();
                case "email" -> c.email = p.getValueAsString();
                case "ssn" -> c.ssn = p.getValueAsString();
                case "risk" -> c.risk = p.getValueAsString();
                default -> p.skipChildren();
            }
        }
    }

    private static void readMetrics(JsonParser p, Core c) throws IOException {
        requireObject(p, "metrics");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "load" -> c.load = p.getValueAsString();
                case "tempC" -> c.temperature = p.getDecimalValue();
                case "online" -> c.online = p.getBooleanValue();
                default -> p.skipChildren();
            }
        }
    }

    private static void readSignals(JsonParser p, Core c) throws IOException {
        require(p.currentToken() == JsonToken.START_ARRAY, "signals must be an array");
        int index = 0;
        while (p.nextToken() != JsonToken.END_ARRAY) {
            require(index < c.signalNames.length, "signals exceeds fixed benchmark cardinality");
            requireObject(p, "signals[]");
            while (p.nextToken() != JsonToken.END_OBJECT) {
                String n = p.currentName();
                p.nextToken();
                switch (n) {
                    case "name" -> c.signalNames[index] = p.getValueAsString();
                    case "value" -> c.signalValues[index] = p.getIntValue();
                    case "category" -> c.signalCategories[index] = p.getValueAsString();
                    default -> p.skipChildren();
                }
            }
            index++;
        }
        c.signalCount = index;
    }

    private static void readSingleSignals(JsonParser p, Core c) throws IOException {
        require(p.currentToken() == JsonToken.START_ARRAY, "singleSignals must be an array");
        while (p.nextToken() != JsonToken.END_ARRAY) {
            requireObject(p, "singleSignals[]");
            while (p.nextToken() != JsonToken.END_OBJECT) {
                String n = p.currentName();
                p.nextToken();
                if ("name".equals(n)) c.onlySignal = p.getValueAsString();
                else p.skipChildren();
            }
        }
    }

    private static void readPacket(JsonParser p, Core c) throws IOException {
        requireObject(p, "packet");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            switch (n) {
                case "labels" -> c.labels = p.getValueAsString();
                case "message" -> c.message = p.getValueAsString();
                case "policyNumber" -> c.policyNumber = p.getValueAsString();
                case "jsonObjectText" -> c.jsonObjectText = p.getValueAsString();
                case "jsonArrayText" -> c.jsonArrayText = p.getValueAsString();
                case "businessDate" -> c.businessDate = p.getValueAsString();
                case "shipTime" -> c.shipTime = p.getValueAsString();
                default -> p.skipChildren();
            }
        }
    }

    private static void readBenchmark(JsonParser p, Core c) throws IOException {
        requireObject(p, "benchmark");
        while (p.nextToken() != JsonToken.END_OBJECT) {
            String n = p.currentName();
            p.nextToken();
            if ("mappingSchemaVersion".equals(n)) c.mappingSchemaVersion = p.getValueAsString();
            else p.skipChildren();
        }
    }

    private static List<MappingError> policyErrors(Core c) {
        List<MappingError> errors = new ArrayList<>(4);
        if (c.eventId == null || !c.eventId.startsWith("evt-benchmark-")) {
            errors.add(new MappingError("eventId", "REGEX_FAILED", "Value did not match validation pattern"));
        }
        if (c.orderStatus != null
                && !c.orderStatus.equals("submitted")
                && !c.orderStatus.equals("cancelled")) {
            errors.add(new MappingError("normalizedStatus", "LOOKUP_MISSING",
                    "No lookup value for '" + c.orderStatus + "'"));
        }
        try {
            new BigDecimal(c.amount);
        } catch (RuntimeException e) {
            errors.add(new MappingError("orderAmountDouble", "TYPE_CONVERSION_FAILED",
                    "Failed to cast value to double (invalid_number)"));
            errors.add(new MappingError("amountRounded", "TYPE_CONVERSION_FAILED",
                    "Failed to cast value to decimal (invalid_number)"));
            errors.add(new MappingError("functionRound", "TYPE_CONVERSION_FAILED",
                    "Failed to cast value to target type (invalid_number)"));
            errors.add(new MappingError("decimalTruncated", "TYPE_CONVERSION_FAILED",
                    "Failed to cast value to decimal (invalid_number)"));
        }
        required(c.campaignId, "$.run.campaignId");
        required(c.orderId, "$.order.id");
        required(c.region, "$.tenant.region");
        required(c.customerId, "$.customer.id");
        require(c.signalCount == 3, "$.signals must contain exactly three benchmark items");
        return errors;
    }

    private static void writeCore(Utf8Writer w, Core c, RecordContext context) {
        BigDecimal amount = decimal(c.amount, "$.order.amount");
        int load = integer(c.load, "$.metrics.load");
        w.string("demoRunId", c.campaignId);
        w.number("sequence", Long.toString(c.sequence));
        w.string("eventId", c.eventId);
        w.string("orderId", c.orderId);
        w.string("customerTier", upper(c.tier));
        w.string("normalizedStatus", switch (c.orderStatus) {
            case "submitted" -> "ACCEPTED";
            case "cancelled" -> "CANCELLED";
            default -> throw new MappingException("TRANSFORMATION_ERROR", "statusCode lookup miss");
        });
        w.number("orderAmountDouble", Double.toString(amount.doubleValue()));
        w.number("amountRounded", amount.setScale(2, RoundingMode.HALF_UP).toPlainString());
        w.string("eventTypeUpper", upper(c.eventType));
        w.string("eventTypeLower", lower(c.eventType));
        w.number("receivedAt", Long.toString(Instant.parse(c.eventTimestamp).toEpochMilli()));
        w.string("region", c.region);
        w.string("runtimeConstant", "flowplane-http-grpc-benchmark");
        w.string("customerLabel", "customer-" + c.customerId);
        w.stringArray("labelParts", c.labels.split("\\|", -1));
        w.string("normalizedMessage", normalize(c.message));
        w.number("loadPlusTen", BigDecimal.valueOf(load + 10L).stripTrailingZeros().toString());
        w.number("hugeIntClamped", "2147483647");
        w.number("badIntDefault", "-1");
        w.string("customerEmailMasked", maskLast4(c.email));
        w.string("customerSsnHashed", sha256(c.ssn));
        w.string("traceHash", sha256(c.trace));
        w.string("mappingSchemaVersion", c.mappingSchemaVersion);
        w.string("signalNames", String.join("|", Arrays.copyOf(c.signalNames, c.signalCount)));
        w.number("signalCount", Integer.toString(c.signalCount));
        w.string("firstHotSignal", firstSignalAtLeast(c, 70));
        w.string("filterFirstSignal", c.signalNames[0]);
        w.number("temperature", c.temperature.setScale(1, RoundingMode.HALF_UP).toPlainString());
        w.bool("online", c.online);
        w.string("currencyLabel", "currency-" + c.currency);
        w.string("riskBand", c.risk);
        w.string("defaultedValue", "fixture-default");
        w.nullableString("metadataTenant", context.metadataTenant());
        w.nullableString("headerSource", context.headerSource());
        w.number("loadAsInt", Integer.toString(load));
        w.number("loadAsLong", Long.toString(load));
        w.raw("jsonObject", c.jsonObjectText);
        w.raw("jsonArray", c.jsonArrayText);
        String[] date = c.businessDate.split("/");
        w.string("businessDate", date[2] + "-" + date[0] + "-" + date[1]);
        w.string("shipTime", c.shipTime.endsWith(":00") ? c.shipTime.substring(0, 5) : c.shipTime);
        w.string("regexMatched", c.orderId);
        w.string("regexExtracted", "****");
        w.string("regexReplaced", maskLast4(c.ssn.replace("-", "")));
        w.string("sensitiveEmail", maskLast4(c.email));
        w.string("redactedSsn", "****");
        w.string("lastSignal", c.signalNames[c.signalCount - 1]);
        w.string("onlySignal", c.onlySignal);
        w.string("indexedSignal", c.signalNames[1]);
        w.stringArray("collectedSignals", Arrays.copyOf(c.signalNames, c.signalCount));
        w.filteredSignalNames("filteredSignals", c, 70, true);
        w.stringArray("flattenedSignals", Arrays.copyOf(c.signalNames, c.signalCount));
        w.stringArray("distinctSignalCategories", Arrays.copyOf(c.signalCategories, c.signalCount));
        int sum = 0, min = Integer.MAX_VALUE, max = Integer.MIN_VALUE;
        for (int i = 0; i < c.signalCount; i++) {
            sum += c.signalValues[i];
            min = Math.min(min, c.signalValues[i]);
            max = Math.max(max, c.signalValues[i]);
        }
        w.number("signalValueSum", compactDecimal(sum));
        w.number("signalValueMin", compactDecimal(min));
        w.number("signalValueMax", compactDecimal(max));
        w.number("signalValueCount", Integer.toString(c.signalCount));
        w.mappedHotSignals("mappedHotSignals", c);
        BigDecimal fahrenheit = c.temperature.multiply(new BigDecimal("1.8")).add(new BigDecimal("32"));
        w.number("arithmeticExpression", fahrenheit.setScale(2, RoundingMode.HALF_UP).toPlainString());
        w.bool("booleanExpression", load >= 50);
        w.string("policyPrefix", c.policyNumber.substring(0, 7));
        w.objectProjection("objectProjection", c);
        w.mergedContext("mergedContext", c);
        w.string("coalescedValue", c.customerId);
        w.string("caseValue", load >= 50 ? "loaded" : "idle");
        w.string("lookupExpression", c.risk);
        w.string("functionConcat", c.orderId + "-" + c.customerId);
        w.string("functionUpper", upper(c.orderStatus));
        w.string("functionLower", lower(c.orderStatus));
        w.string("functionTrim", c.message.trim());
        w.string("functionSubstring", c.policyNumber.substring(4, 7));
        w.stringArray("functionSplit", c.policyNumber.split("-", -1));
        w.number("functionRound", amount.setScale(1, RoundingMode.HALF_UP).toPlainString());
        w.string("functionHash", sha256(c.email));
        w.nullValue("missingAsNull");
        w.string("itemsAsJson", canonicalSignals(c));
        w.string("customerAsJson", canonicalCustomer(c));
        w.number("decimalTruncated", amount.setScale(1, RoundingMode.DOWN).toPlainString());
    }

    private static void writeWide(JsonParser p, Utf8Writer w, Core c) throws IOException {
        int expected = 1;
        MessageDigest digest = digest();
        byte[] scratch = new byte[14];
        String regionUpper = upper(c.region);
        String tierLower = lower(c.tier);
        String currencyLower = lower(c.currency);
        while (p.nextToken() != JsonToken.END_OBJECT) {
            require(p.currentToken() == JsonToken.FIELD_NAME, "wide field name expected");
            String sourceName = p.currentName();
            require(sourceName.equals(SOURCE_WIDE_NAMES[expected - 1]),
                    "unexpected wide field order at " + sourceName);
            require(p.nextToken() == JsonToken.VALUE_STRING, "$.wide." + sourceName + " must be a string");
            if (expected > WIDE_FIELD_COUNT) {
                expected++;
                continue;
            }
            char[] chars = p.getTextCharacters();
            int offset = p.getTextOffset();
            int length = p.getTextLength();
            String targetName = TARGET_WIDE_NAMES[expected - 1];
            w.name(targetName);
            w.quote();
            switch ((expected - 1) & 7) {
                case 0 -> {
                    w.ascii("normalized-WIDE");
                    w.chars(chars, offset + 5, length - 5, Utf8Writer.Mode.PLAIN);
                }
                case 1 -> {
                    w.ascii("extracted-");
                    w.chars(chars, offset + 6, length - 6, Utf8Writer.Mode.PLAIN);
                }
                case 2 -> {
                    w.ascii("slice-");
                    w.chars(chars, offset, Math.min(14, length), Utf8Writer.Mode.HYPHEN_TO_COLON);
                }
                case 3 -> {
                    w.ascii("joined-");
                    w.chars(chars, offset, length, Utf8Writer.Mode.UPPER);
                    w.ascii(":");
                    w.ascii(regionUpper);
                }
                case 4 -> w.chars(chars, offset, length, Utf8Writer.Mode.LOWER_HYPHEN_TO_UNDERSCORE);
                case 5 -> {
                    w.ascii("validated-");
                    w.chars(chars, offset, length, Utf8Writer.Mode.UPPER);
                }
                case 6 -> {
                    w.ascii("digest-");
                    int n = Math.min(14, length);
                    for (int i = 0; i < n; i++) scratch[i] = (byte) chars[offset + i];
                    digest.update(scratch, 0, n);
                    byte[] hash = digest.digest();
                    w.hex(hash);
                    digest.reset();
                }
                case 7 -> {
                    w.ascii("context-");
                    w.chars(chars, offset, length, Utf8Writer.Mode.LOWER_HYPHEN_TO_UNDERSCORE);
                    w.ascii(":");
                    w.ascii(tierLower);
                    w.ascii(":");
                    w.ascii(currencyLower);
                }
                default -> throw new AssertionError();
            }
            w.quote();
            expected++;
        }
        require(expected > WIDE_FIELD_COUNT,
                "expected at least " + WIDE_FIELD_COUNT + " wide fields, got " + (expected - 1));
    }

    private static String canonicalSignals(Core c) {
        StringBuilder b = new StringBuilder(180).append('[');
        for (int i = 0; i < c.signalCount; i++) {
            if (i > 0) b.append(',');
            b.append("{\"name\":\"").append(c.signalNames[i]).append("\",\"value\":")
                    .append(c.signalValues[i]).append(",\"category\":\"")
                    .append(c.signalCategories[i]).append("\"}");
        }
        return b.append(']').toString();
    }

    private static String canonicalCustomer(Core c) {
        return "{\"id\":\"" + c.customerId + "\",\"tier\":\"" + c.tier
                + "\",\"email\":\"" + c.email + "\",\"ssn\":\"" + c.ssn
                + "\",\"risk\":\"" + c.risk + "\"}";
    }

    private static String firstSignalAtLeast(Core c, int threshold) {
        for (int i = 0; i < c.signalCount; i++) if (c.signalValues[i] >= threshold) return c.signalNames[i];
        return null;
    }

    private static String normalize(String value) {
        StringBuilder b = new StringBuilder(value.length());
        boolean whitespace = true;
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (Character.isWhitespace(ch)) {
                whitespace = true;
            } else {
                if (whitespace && !b.isEmpty()) b.append(' ');
                b.append(ch);
                whitespace = false;
            }
        }
        return b.toString();
    }

    private static String maskLast4(String value) {
        int visible = Math.min(4, value.length());
        return "*".repeat(Math.max(0, value.length() - visible)) + value.substring(value.length() - visible);
    }

    private static String sha256(String value) {
        byte[] bytes = digest().digest(value.getBytes(StandardCharsets.UTF_8));
        byte[] hex = new byte[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            hex[i * 2] = HEX[(bytes[i] >>> 4) & 0xf];
            hex[i * 2 + 1] = HEX[bytes[i] & 0xf];
        }
        return new String(hex, StandardCharsets.US_ASCII);
    }

    private static MessageDigest digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String upper(String v) {
        return v == null ? null : v.toUpperCase(Locale.ROOT);
    }

    private static String compactDecimal(long value) {
        return BigDecimal.valueOf(value).stripTrailingZeros().toString();
    }

    private static String lower(String v) {
        return v == null ? null : v.toLowerCase(Locale.ROOT);
    }

    private static BigDecimal decimal(String v, String path) {
        try {
            return new BigDecimal(v);
        } catch (RuntimeException e) {
            throw new MappingException("TYPE_MISMATCH", path + " is not decimal");
        }
    }

    private static int integer(String v, String path) {
        try {
            return Integer.parseInt(v);
        } catch (RuntimeException e) {
            throw new MappingException("TYPE_MISMATCH", path + " is not int");
        }
    }

    private static void required(String value, String path) {
        if (value == null || value.isEmpty()) throw new MappingException("VALIDATION_FAILURE", path + " is required");
    }

    private static void requireObject(JsonParser p, String path) {
        require(p.currentToken() == JsonToken.START_OBJECT, path + " must be an object");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new MappingException("VALIDATION_FAILURE", message);
    }

    private static String safeMessage(Throwable e) {
        String m = e.getMessage();
        return m == null || m.isBlank() ? e.getClass().getSimpleName() : m;
    }

    private static String[] fieldNames(String prefix, int count) {
        String[] names = new String[count];
        for (int i = 1; i <= count; i++) {
            int value = i;
            char[] digits = {'0', '0', '0', '0'};
            for (int at = 3; at >= 0; at--) {
                digits[at] = (char) ('0' + (value % 10));
                value /= 10;
            }
            names[i - 1] = prefix + new String(digits);
        }
        return names;
    }

    private static String trailingAsciiString(byte[] payload, String marker) {
        byte[] needle = marker.getBytes(StandardCharsets.US_ASCII);
        outer:
        for (int i = payload.length - needle.length; i >= 0; i--) {
            for (int j = 0; j < needle.length; j++) {
                if (payload[i + j] != needle[j]) continue outer;
            }
            int start = i + needle.length;
            int end = start;
            while (end < payload.length && payload[end] != '"') end++;
            if (end == payload.length) throw new MappingException("TRANSFORMATION_ERROR", "unterminated mappingSchemaVersion");
            return new String(payload, start, end - start, StandardCharsets.US_ASCII);
        }
        return null;
    }

    public record RecordContext(String metadataTenant, String headerSource) {
        public static final RecordContext EMPTY = new RecordContext(null, null);
    }

    public record MappingError(String field, String code, String message) {}

    public record Result(Status status, byte[] output, List<MappingError> fieldErrors) {
        static Result output(byte[] output) { return new Result(Status.OUTPUT, output, List.of()); }
        static Result dlq(List<MappingError> errors) { return new Result(Status.DLQ, null, List.copyOf(errors)); }
    }

    public enum Status { OUTPUT, DLQ }

    private static final class MappingException extends RuntimeException {
        private final String code;
        private final List<MappingError> errors;
        private MappingException(String code, String message) {
            super(message);
            this.code = code;
            this.errors = null;
        }
        private MappingException(List<MappingError> errors) {
            super(errors.getFirst().message());
            this.code = errors.getFirst().code();
            this.errors = List.copyOf(errors);
        }
    }

    private static final class Core {
        String campaignId, eventId, eventType, eventTimestamp, trace, region;
        String orderId, orderStatus, amount, currency;
        String customerId, tier, email, ssn, risk;
        String load, onlySignal, labels, message, policyNumber;
        String jsonObjectText, jsonArrayText, businessDate, shipTime, mappingSchemaVersion;
        long sequence;
        BigDecimal temperature;
        boolean online;
        int signalCount;
        final String[] signalNames = new String[3];
        final String[] signalCategories = new String[3];
        final int[] signalValues = new int[3];
    }

    private static final class Utf8Writer {
        enum Mode { PLAIN, UPPER, HYPHEN_TO_COLON, LOWER_HYPHEN_TO_UNDERSCORE }
        private final ByteArrayOutputStream out;
        private boolean first = true;

        Utf8Writer(int size) { out = new ByteArrayOutputStream(size); }
        void beginObject() { out.write('{'); }
        void endObject() { out.write('}'); }
        byte[] toByteArray() { return out.toByteArray(); }

        void name(String name) {
            if (!first) out.write(',');
            first = false;
            quote();
            ascii(name);
            quote();
            out.write(':');
        }

        void string(String name, String value) { name(name); stringValue(value); }
        void nullableString(String name, String value) { if (value == null) nullValue(name); else string(name, value); }
        void number(String name, String value) { name(name); ascii(value); }
        void bool(String name, boolean value) { name(name); ascii(value ? "true" : "false"); }
        void raw(String name, String value) { name(name); ascii(value); }
        void nullValue(String name) { name(name); ascii("null"); }
        void quote() { out.write('"'); }

        void stringValue(String value) {
            if (value == null) { ascii("null"); return; }
            quote();
            for (int i = 0; i < value.length(); i++) escaped(value.charAt(i));
            quote();
        }

        void stringArray(String name, String[] values) {
            name(name);
            out.write('[');
            for (int i = 0; i < values.length; i++) {
                if (i > 0) out.write(',');
                stringValue(values[i]);
            }
            out.write(']');
        }

        void filteredSignalNames(String name, Core c, int threshold, boolean inclusive) {
            name(name);
            out.write('[');
            boolean itemFirst = true;
            for (int i = 0; i < c.signalCount; i++) {
                if (inclusive ? c.signalValues[i] >= threshold : c.signalValues[i] > threshold) {
                    if (!itemFirst) out.write(',');
                    itemFirst = false;
                    stringValue(c.signalNames[i]);
                }
            }
            out.write(']');
        }

        void mappedHotSignals(String name, Core c) {
            name(name);
            out.write('[');
            boolean itemFirst = true;
            for (int i = 0; i < c.signalCount; i++) {
                if (c.signalValues[i] > 70) {
                    if (!itemFirst) out.write(',');
                    itemFirst = false;
                    ascii("{\"name\":");
                    stringValue(c.signalNames[i]);
                    ascii(",\"category\":");
                    stringValue(c.signalCategories[i]);
                    out.write('}');
                }
            }
            out.write(']');
        }

        void objectProjection(String name, Core c) {
            name(name);
            ascii("{\"order\":{\"id\":");
            stringValue(c.orderId);
            ascii("},\"event\":{\"id\":");
            stringValue(c.eventId);
            ascii("}}");
        }

        void mergedContext(String name, Core c) {
            name(name);
            ascii("{\"id\":"); stringValue(c.customerId);
            ascii(",\"status\":"); stringValue(c.orderStatus);
            ascii(",\"amount\":"); stringValue(c.amount);
            ascii(",\"currency\":"); stringValue(c.currency);
            ascii(",\"tier\":"); stringValue(c.tier);
            ascii(",\"email\":"); stringValue(c.email);
            ascii(",\"ssn\":"); stringValue(c.ssn);
            ascii(",\"risk\":"); stringValue(c.risk);
            out.write('}');
        }

        void chars(char[] chars, int offset, int length, Mode mode) {
            for (int i = 0; i < length; i++) {
                char ch = chars[offset + i];
                if (mode == Mode.UPPER) ch = Character.toUpperCase(ch);
                else if (mode == Mode.HYPHEN_TO_COLON && ch == '-') ch = ':';
                else if (mode == Mode.LOWER_HYPHEN_TO_UNDERSCORE) {
                    if (ch == '-') ch = '_';
                    else ch = Character.toLowerCase(ch);
                }
                escaped(ch);
            }
        }

        void hex(byte[] bytes) {
            for (byte b : bytes) {
                out.write(HEX[(b >>> 4) & 0xf]);
                out.write(HEX[b & 0xf]);
            }
        }

        void ascii(String value) {
            for (int i = 0; i < value.length(); i++) {
                char ch = value.charAt(i);
                if (ch < 0x80) out.write((byte) ch);
                else out.writeBytes(String.valueOf(ch).getBytes(StandardCharsets.UTF_8));
            }
        }

        private void escaped(char ch) {
            switch (ch) {
                case '"' -> ascii("\\\"");
                case '\\' -> ascii("\\\\");
                case '\b' -> ascii("\\b");
                case '\f' -> ascii("\\f");
                case '\n' -> ascii("\\n");
                case '\r' -> ascii("\\r");
                case '\t' -> ascii("\\t");
                default -> {
                    if (ch < 0x20) ascii(String.format(Locale.ROOT, "\\u%04x", (int) ch));
                    else if (ch < 0x80) out.write((byte) ch);
                    else out.writeBytes(String.valueOf(ch).getBytes(StandardCharsets.UTF_8));
                }
            }
        }
    }
}
