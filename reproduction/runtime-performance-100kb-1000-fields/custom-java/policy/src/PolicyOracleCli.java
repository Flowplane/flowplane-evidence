import java.lang.reflect.Method;
import java.lang.reflect.InvocationTargetException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;

/**
 * Exports the exact governed-core result for the benchmark policy canaries.
 *
 * <p>This class deliberately uses reflection so the benchmark compiles without
 * linking product code. At execution time the caller must supply the exact
 * FlowPlane Core artifact under test. No records are published.</p>
 */
public final class PolicyOracleCli {
    private PolicyOracleCli() {}

    public static void main(String[] arguments) throws Exception {
        Path mapping = null;
        Path payloads = null;
        Path output = null;
        for (int index = 0; index < arguments.length; index += 2) {
            switch (arguments[index]) {
                case "--mapping" -> mapping = Path.of(arguments[index + 1]);
                case "--payload-jsonl" -> payloads = Path.of(arguments[index + 1]);
                case "--output" -> output = Path.of(arguments[index + 1]);
                default -> throw new IllegalArgumentException("unknown argument " + arguments[index]);
            }
        }
        if (mapping == null || payloads == null || output == null) {
            throw new IllegalArgumentException(
                "usage: --mapping <mapping.dsl> --payload-jsonl <invalid.jsonl> --output <oracle.jsonl>");
        }
        if (Files.exists(output)) {
            throw new IllegalStateException("refusing to overwrite oracle evidence: " + output);
        }
        Files.createDirectories(output.toAbsolutePath().getParent());

        Class<?> flowPlane = Class.forName("com.flowplane.core.FlowPlane");
        Class<?> compiledType = Class.forName("com.flowplane.core.CompiledMapping");
        Class<?> optionsType = Class.forName("com.flowplane.core.RuntimeOutputOptions");
        Class<?> outputShapeType = Class.forName("com.flowplane.core.OutputShape");
        Class<?> resultType = Class.forName("com.flowplane.core.TransformResult");
        Class<?> fieldErrorType = Class.forName("com.flowplane.core.FieldError");
        Object compiled = flowPlane.getMethod("compile", String.class)
            .invoke(null, Files.readString(mapping, StandardCharsets.UTF_8));
        @SuppressWarnings({"unchecked", "rawtypes"})
        Object bytesShape = Enum.valueOf(
            (Class<? extends Enum>) outputShapeType.asSubclass(Enum.class), "BYTES");
        Object options = optionsType.getMethod("shape", outputShapeType).invoke(null, bytesShape);
        Method transform = compiledType.getMethod("transform", byte[].class, optionsType);
        Method errorPolicy = compiledType.getMethod("errorPolicy");
        Method success = resultType.getMethod("success");
        Method errors = resultType.getMethod("errors");
        Method value = resultType.getMethod("value");
        Method field = fieldErrorType.getMethod("field");
        Method code = fieldErrorType.getMethod("code");
        Method message = fieldErrorType.getMethod("message");

        Object policy = errorPolicy.invoke(compiled);
        Method transformationAction = policy.getClass().getMethod("onTransformationError");
        Method validationAction = policy.getClass().getMethod("onValidationFailure");
        Method typeMismatchAction = policy.getClass().getMethod("onTypeMismatch");
        String policyJson = "{\"onTransformationError\":\""
            + transformationAction.invoke(policy) + "\",\"onValidationFailure\":\""
            + validationAction.invoke(policy) + "\",\"onTypeMismatch\":\""
            + typeMismatchAction.invoke(policy) + "\"}";

        List<String> lines = Files.readAllLines(payloads, StandardCharsets.UTF_8);
        try (var writer = Files.newBufferedWriter(output, StandardCharsets.UTF_8)) {
            for (int index = 0; index < lines.size(); index++) {
                byte[] input = lines.get(index).getBytes(StandardCharsets.UTF_8);
                Object result;
                try {
                    result = transform.invoke(compiled, input, options);
                } catch (InvocationTargetException invocation) {
                    Throwable cause = invocation.getCause();
                    String exceptionCode;
                    try {
                        exceptionCode = String.valueOf(cause.getClass().getMethod("code").invoke(cause));
                    } catch (ReflectiveOperationException ignored) {
                        exceptionCode = cause.getClass().getSimpleName();
                    }
                    writer.write("{\"index\":" + index
                        + ",\"inputBytes\":" + input.length
                        + ",\"inputSha256\":\"" + sha256(input) + "\""
                        + ",\"errorPolicy\":" + policyJson
                        + ",\"status\":\"DLQ\",\"exception\":{"
                        + "\"code\":\"" + json(exceptionCode) + "\","
                        + "\"message\":\"" + json(String.valueOf(cause.getMessage())) + "\"}}\n");
                    continue;
                }
                @SuppressWarnings("unchecked")
                List<Object> resultErrors = (List<Object>) errors.invoke(result);
                boolean succeeded = Boolean.TRUE.equals(success.invoke(result));
                writer.write("{\"index\":" + index
                    + ",\"inputBytes\":" + input.length
                    + ",\"inputSha256\":\"" + sha256(input) + "\""
                    + ",\"errorPolicy\":" + policyJson
                    + ",\"status\":\"" + (succeeded ? "OUTPUT" : "DLQ") + "\"");
                if (succeeded) {
                    byte[] transformed = (byte[]) value.invoke(result);
                    writer.write(",\"outputBytes\":" + transformed.length
                        + ",\"outputSha256\":\"" + sha256(transformed) + "\""
                        + ",\"outputBase64\":\""
                        + Base64.getEncoder().encodeToString(transformed) + "\"");
                } else {
                    writer.write(",\"fieldErrors\":[");
                    for (int errorIndex = 0; errorIndex < resultErrors.size(); errorIndex++) {
                        if (errorIndex > 0) writer.write(",");
                        Object error = resultErrors.get(errorIndex);
                        writer.write("{\"field\":\"" + json(String.valueOf(field.invoke(error)))
                            + "\",\"code\":\"" + json(String.valueOf(code.invoke(error)))
                            + "\",\"message\":\"" + json(String.valueOf(message.invoke(error))) + "\"}");
                    }
                    writer.write("]");
                }
                writer.write("}");
                writer.write("\n");
            }
        }
    }

    private static String sha256(byte[] value) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
    }

    private static String json(String value) {
        StringBuilder escaped = new StringBuilder(value.length() + 16);
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            switch (character) {
                case '"' -> escaped.append("\\\"");
                case '\\' -> escaped.append("\\\\");
                case '\b' -> escaped.append("\\b");
                case '\f' -> escaped.append("\\f");
                case '\n' -> escaped.append("\\n");
                case '\r' -> escaped.append("\\r");
                case '\t' -> escaped.append("\\t");
                default -> {
                    if (character < 0x20) {
                        escaped.append(String.format("\\u%04x", (int) character));
                    } else {
                        escaped.append(character);
                    }
                }
            }
        }
        return escaped.toString();
    }
}
