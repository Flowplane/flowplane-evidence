package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class PayloadSetTest {
    @TempDir Path temporary;

    @Test void usesRoundRobinWithoutExpandingTheFixture() throws Exception {
        Path fixture = temporary.resolve("payloads.jsonl");
        Files.writeString(fixture, "aaaa\nbbbb\n");
        PayloadSet set = PayloadSet.load(fixture, 2, 4);
        assertEquals("aaaa", set.at(0).toStringUtf8());
        assertEquals("bbbb", set.at(1).toStringUtf8());
        assertEquals("aaaa", set.at(2).toStringUtf8());
        assertEquals(2, set.hashes().size());
    }

    @Test void rejectsUnexpectedPayloadSize() throws Exception {
        Path fixture = temporary.resolve("payloads.jsonl");
        Files.writeString(fixture, "short\n");
        assertThrows(IllegalArgumentException.class, () -> PayloadSet.load(fixture, 1, 4));
    }
}
