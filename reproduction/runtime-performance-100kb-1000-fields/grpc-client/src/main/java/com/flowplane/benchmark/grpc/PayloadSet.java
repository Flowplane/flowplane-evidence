package com.flowplane.benchmark.grpc;

import com.google.protobuf.ByteString;
import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

final class PayloadSet {
    private final List<ByteString> payloads;
    private final List<String> hashes;

    private PayloadSet(List<ByteString> payloads, List<String> hashes) {
        this.payloads = List.copyOf(payloads);
        this.hashes = List.copyOf(hashes);
    }

    static PayloadSet load(Path path, int expectedCount, int expectedBytes) throws IOException {
        List<ByteString> payloads = new ArrayList<>(expectedCount);
        List<String> hashes = new ArrayList<>(expectedCount);
        try (BufferedReader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) continue;
                byte[] bytes = line.getBytes(StandardCharsets.UTF_8);
                if (bytes.length != expectedBytes) {
                    throw new IllegalArgumentException("payload " + payloads.size() + " has " + bytes.length
                        + " bytes; expected " + expectedBytes);
                }
                payloads.add(ByteString.copyFrom(bytes));
                hashes.add(sha256(bytes));
            }
        }
        if (payloads.size() != expectedCount) {
            throw new IllegalArgumentException("fixture has " + payloads.size() + " payloads; expected " + expectedCount);
        }
        return new PayloadSet(payloads, hashes);
    }

    ByteString at(long sequence) { return payloads.get((int) (sequence % payloads.size())); }
    int size() { return payloads.size(); }
    List<String> hashes() { return hashes; }

    private static String sha256(byte[] value) {
        try {
            return "sha256:" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }
}
