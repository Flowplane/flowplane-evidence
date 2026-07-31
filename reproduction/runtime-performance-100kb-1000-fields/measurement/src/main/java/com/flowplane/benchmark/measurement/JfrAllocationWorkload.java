package com.flowplane.benchmark.measurement;

/** Short local workload used only to verify that JFR allocation evidence can be parsed. */
public final class JfrAllocationWorkload {
    private JfrAllocationWorkload() {}

    public static void main(String[] args) throws Exception {
        byte[][] retained = new byte[64][];
        long checksum = 0;
        for (int i = 0; i < 50_000; i++) {
            byte[] value = new byte[4096 + (i & 255)];
            value[0] = (byte) i;
            retained[i & 63] = value;
            checksum += value[0];
        }
        Thread.sleep(750);
        if (checksum == Long.MIN_VALUE || retained[0] == null) throw new AssertionError("unreachable");
    }
}
