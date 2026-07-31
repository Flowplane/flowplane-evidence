package com.flowplane.benchmark.measurement;

import java.lang.reflect.Array;
import java.util.Map;

final class Json {
    private Json() {}

    static String write(Object value) {
        StringBuilder out = new StringBuilder(4096);
        append(out, value);
        return out.toString();
    }

    private static void append(StringBuilder out, Object value) {
        if (value == null) out.append("null");
        else if (value instanceof String text) quote(out, text);
        else if (value instanceof Number || value instanceof Boolean) out.append(value);
        else if (value instanceof Map<?, ?> map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (!first) out.append(',');
                first = false;
                quote(out, String.valueOf(entry.getKey()));
                out.append(':');
                append(out, entry.getValue());
            }
            out.append('}');
        } else if (value instanceof Iterable<?> values) {
            out.append('[');
            boolean first = true;
            for (Object item : values) {
                if (!first) out.append(',');
                first = false;
                append(out, item);
            }
            out.append(']');
        } else if (value.getClass().isArray()) {
            out.append('[');
            for (int i = 0; i < Array.getLength(value); i++) {
                if (i > 0) out.append(',');
                append(out, Array.get(value, i));
            }
            out.append(']');
        } else quote(out, String.valueOf(value));
    }

    private static void quote(StringBuilder out, String text) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);
            switch (ch) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\b' -> out.append("\\b");
                case '\f' -> out.append("\\f");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (ch < 0x20) out.append(String.format("\\u%04x", (int) ch));
                    else out.append(ch);
                }
            }
        }
        out.append('"');
    }
}
