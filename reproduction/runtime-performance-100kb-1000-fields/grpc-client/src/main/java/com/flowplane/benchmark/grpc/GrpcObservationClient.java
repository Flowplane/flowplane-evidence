package com.flowplane.benchmark.grpc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.flowplane.runtime.v1.ErrorMode;
import com.flowplane.runtime.v1.FlowPlaneTransformServiceGrpc;
import com.flowplane.runtime.v1.InputFormat;
import com.flowplane.runtime.v1.OutputFormat;
import com.flowplane.runtime.v1.TransformBatchRequest;
import com.flowplane.runtime.v1.TransformRecord;
import com.flowplane.runtime.v1.TransformResult;
import com.flowplane.runtime.v1.TransformStatus;
import com.flowplane.runtime.v1.TransformStreamRequest;
import com.flowplane.runtime.v1.TransformStreamResponse;
import io.grpc.ManagedChannel;
import io.grpc.netty.shaded.io.grpc.netty.NettyChannelBuilder;
import io.grpc.stub.ClientCallStreamObserver;
import io.grpc.stub.ClientResponseObserver;
import java.io.BufferedWriter;
import java.io.Closeable;
import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import jdk.jfr.Configuration;
import jdk.jfr.Recording;

/**
 * Isolated, bounded-memory gRPC streaming load generator.
 *
 * <p>Runtime responses are observed and immediately discarded. The client has no Kafka or other
 * downstream dependency and therefore cannot publish transformed output.</p>
 */
public final class GrpcObservationClient {
    private static final ObjectMapper JSON = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
    private static final ObjectMapper JSON_LINE = new ObjectMapper();
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    private GrpcObservationClient() {}

    public static void main(String[] arguments) throws Exception {
        Config config = Config.parse(arguments);
        Files.createDirectories(config.runDir());
        assertFreshOutputDirectory(config);
        PayloadSet payloads = PayloadSet.load(config.payloadJsonl(), config.payloadVariants(), config.payloadBytes());
        Assignment assignment = fetchAssignment(config);
        if (!config.expectedRuntimeId().equals(assignment.runtimeId())) {
            throw new IllegalStateException("assigned runtime " + assignment.runtimeId()
                + " does not match expected runtime " + config.expectedRuntimeId());
        }
        if (!config.expectedArtifactId().equals(assignment.artifactId())) {
            throw new IllegalStateException("assigned artifact id " + assignment.artifactId()
                + " does not match expected id " + config.expectedArtifactId());
        }
        if (!config.expectedArtifactHash().equals(assignment.artifactHash())) {
            throw new IllegalStateException("assigned artifact hash " + assignment.artifactHash()
                + " does not match expected hash " + config.expectedArtifactHash());
        }
        if (!config.expectedMappingId().equals(assignment.mappingId())) {
            throw new IllegalStateException("assigned mapping " + assignment.mappingId()
                + " does not match expected mapping " + config.expectedMappingId());
        }
        writeManifest(config, assignment, payloads);

        Path partial = config.runDir().resolve("grpc-client-observation.partial.json");
        Path result = config.runDir().resolve("grpc-client-observation.json");
        try (Recording recording = startJfr(config.jfrFile());
             SampleWriter samples = new SampleWriter(config.runDir().resolve("latency-samples.jsonl"), config.sampleEveryBatches());
             ParityWriter parity = new ParityWriter(config.parityEvidencePath())) {
            Observation observation = execute(config, assignment, payloads, samples, parity);
            JSON.writeValue(partial.toFile(), observation.asMap());
            if (recording != null) {
                recording.stop();
                recording.dump(config.jfrFile());
            }
            observation.requireComplete();
            Files.move(partial, result);
            System.out.println(JSON.writeValueAsString(observation.asMap()));
        }
    }

    private static Observation execute(Config config, Assignment assignment, PayloadSet payloads,
                                       SampleWriter samples, ParityWriter parity) throws Exception {
        ManagedChannel channel = NettyChannelBuilder.forAddress(config.host(), config.port())
            .usePlaintext()
            .maxInboundMessageSize(config.maxInboundBytes())
            .build();
        int batchCount = (int) Math.ceil(config.recordCount() / (double) config.batchSize());
        RunState state = new RunState(config, batchCount, samples, parity);
        Instant startedAt = Instant.now();
        long startedNanos = System.nanoTime();
        try {
            FlowPlaneTransformServiceGrpc.FlowPlaneTransformServiceStub stub =
                FlowPlaneTransformServiceGrpc.newStub(channel)
                    .withDeadlineAfter(config.runTimeoutSeconds(), TimeUnit.SECONDS);
            List<StreamSession> sessions = new ArrayList<>(config.streams());
            for (int index = 0; index < config.streams(); index++) {
                sessions.add(new StreamSession(index, stub, state));
            }

            ExecutorService senders = Executors.newFixedThreadPool(config.streams());
            AtomicInteger nextBatch = new AtomicInteger();
            for (StreamSession session : sessions) {
                senders.submit(() -> sendBatches(config, assignment, payloads, state, session, nextBatch, batchCount, startedNanos));
            }
            senders.shutdown();
            if (!senders.awaitTermination(config.runTimeoutSeconds(), TimeUnit.SECONDS)) {
                state.recordError("senders did not terminate before run timeout");
                senders.shutdownNow();
            }
            if (state.stop.get()) sessions.forEach(StreamSession::cancel);
            else sessions.forEach(StreamSession::complete);
            boolean allResponses = !state.stop.get()
                && state.responses.await(config.responseDrainSeconds(), TimeUnit.SECONDS);
            if (!allResponses) state.recordError("response drain timeout with " + state.responses.getCount() + " batches outstanding");
            long closeDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(config.responseDrainSeconds());
            for (StreamSession session : sessions) {
                long remaining = Math.max(0, closeDeadline - System.nanoTime());
                if (!session.awaitClosed(remaining, TimeUnit.NANOSECONDS)) {
                    state.recordError("stream " + session.streamIndex + " did not close before shared drain deadline");
                }
            }
            return state.observation(startedAt, Instant.now(), allResponses);
        } finally {
            channel.shutdown();
            if (!channel.awaitTermination(10, TimeUnit.SECONDS)) channel.shutdownNow();
        }
    }

    private static void sendBatches(Config config, Assignment assignment, PayloadSet payloads, RunState state,
                                    StreamSession session, AtomicInteger nextBatch, int batchCount,
                                    long startedNanos) {
        while (!state.stop.get()) {
            int batchIndex = nextBatch.getAndIncrement();
            if (batchIndex >= batchCount) return;
            try {
                state.inflight.acquire();
                if (state.stop.get()) {
                    state.inflight.release();
                    return;
                }
                int firstRecord = batchIndex * config.batchSize();
                int count = Math.min(config.batchSize(), config.recordCount() - firstRecord);
                pace(config.targetRps(), startedNanos, firstRecord);
                long allocationBefore = allocatedBytes();
                TransformBatchRequest request = request(assignment, payloads, firstRecord, count);
                long sentNanos = System.nanoTime();
                String batchId = "grpc-observed-" + batchIndex;
                Flight flight = new Flight(sentNanos, firstRecord, count);
                state.registerFlight(batchId, flight);
                try {
                    session.send(TransformStreamRequest.newBuilder().setBatchId(batchId).setBatch(request).build());
                } catch (InterruptedException | RuntimeException | Error throwable) {
                    state.abandonFlight(batchId, flight);
                    throw throwable;
                }
                long allocationAfter = allocatedBytes();
                if (allocationBefore >= 0 && allocationAfter >= allocationBefore) {
                    state.requestAllocationBytesPerRecord.record((allocationAfter - allocationBefore) / Math.max(1, count));
                }
                state.sentRecords.add(count);
                state.sentBatches.increment();
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                state.recordError("sender interrupted");
                return;
            } catch (Throwable throwable) {
                state.recordError("send failed: " + throwable.getClass().getSimpleName() + ": " + throwable.getMessage());
                return;
            }
        }
    }

    private static TransformBatchRequest request(Assignment assignment, PayloadSet payloads, int first, int count) {
        TransformBatchRequest.Builder request = TransformBatchRequest.newBuilder()
            .setTenantId(assignment.tenantId())
            .setRuntimeId(assignment.runtimeId())
            .setMappingId(assignment.mappingId())
            .setMappingVersion(assignment.mappingVersion())
            .setArtifactHash(assignment.artifactHash())
            .setInputFormat(InputFormat.JSON)
            .setOutputFormat(OutputFormat.OUTPUT_JSON)
            .setErrorMode(ErrorMode.PER_RECORD);
        for (int offset = 0; offset < count; offset++) {
            long sequence = (long) first + offset;
            String recordId = "grpc-record-" + sequence;
            request.addRecords(TransformRecord.newBuilder()
                .setRecordId(recordId)
                .putHeaders("x-trace-id", recordId)
                .putHeaders("x-benchmark-source", "isolated-grpc-observation-client")
                .setPayload(payloads.at(sequence)));
        }
        return request.build();
    }

    private static void pace(int targetRps, long startedNanos, int recordsScheduled) throws InterruptedException {
        if (targetRps <= 0) return;
        long targetNanos = startedNanos + recordsScheduled * 1_000_000_000L / targetRps;
        long remaining = targetNanos - System.nanoTime();
        if (remaining > 0) TimeUnit.NANOSECONDS.sleep(remaining);
    }

    static final class StreamSession implements ClientResponseObserver<TransformStreamRequest, TransformStreamResponse> {
        private final int streamIndex;
        private final RunState state;
        private final CountDownLatch initialized = new CountDownLatch(1);
        private final CountDownLatch closed = new CountDownLatch(1);
        private volatile ClientCallStreamObserver<TransformStreamRequest> request;

        StreamSession(int streamIndex, FlowPlaneTransformServiceGrpc.FlowPlaneTransformServiceStub stub, RunState state) {
            this.streamIndex = streamIndex;
            this.state = state;
            stub.transformStream(this);
        }

        @Override public void beforeStart(ClientCallStreamObserver<TransformStreamRequest> observer) {
            this.request = observer;
            initialized.countDown();
        }

        void send(TransformStreamRequest value) throws InterruptedException {
            if (!initialized.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("stream did not initialize");
            while (!request.isReady() && !state.stop.get()) TimeUnit.MILLISECONDS.sleep(1);
            if (state.stop.get()) throw new IllegalStateException("stream stopped");
            request.onNext(value);
        }

        void complete() {
            try {
                if (initialized.await(10, TimeUnit.SECONDS) && request != null && !state.stop.get()) request.onCompleted();
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            }
        }

        void cancel() {
            try {
                if (initialized.await(10, TimeUnit.SECONDS) && request != null) {
                    request.cancel("benchmark campaign aborted after first RPC error", null);
                }
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            }
        }

        boolean awaitClosed(long timeout, TimeUnit unit) throws InterruptedException {
            return closed.await(timeout, unit);
        }

        @Override public void onNext(TransformStreamResponse response) {
            state.accept(response, streamIndex);
        }

        @Override public void onError(Throwable throwable) {
            state.recordError("stream " + streamIndex + " error: " + throwable.getClass().getSimpleName() + ": " + throwable.getMessage());
            closed.countDown();
        }

        @Override public void onCompleted() { closed.countDown(); }
    }

    static final class RunState {
        final Config config;
        final Semaphore inflight;
        final CountDownLatch responses;
        final ConcurrentHashMap<String, Flight> pending = new ConcurrentHashMap<>();
        final LongHistogram responseLatencyNanos;
        final LongHistogram requestAllocationBytesPerRecord;
        final LongAdder sentRecords = new LongAdder();
        final LongAdder sentBatches = new LongAdder();
        final LongAdder responseRecords = new LongAdder();
        final LongAdder responseBatches = new LongAdder();
        final AtomicLong responseSequence = new AtomicLong();
        final LongAdder ok = new LongAdder();
        final LongAdder dlq = new LongAdder();
        final LongAdder failed = new LongAdder();
        final LongAdder outputBytes = new LongAdder();
        final AtomicInteger activeInflight = new AtomicInteger();
        final AtomicInteger peakInflight = new AtomicInteger();
        final AtomicBoolean stop = new AtomicBoolean();
        final AtomicReference<String> firstError = new AtomicReference<>();
        final SampleWriter samples;
        final ParityWriter parity;

        RunState(Config config, int batchCount, SampleWriter samples) {
            this(config, batchCount, samples, new ParityWriter());
        }

        RunState(Config config, int batchCount, SampleWriter samples, ParityWriter parity) {
            this.config = config;
            this.inflight = new Semaphore(config.maxInflightBatches());
            this.responses = new CountDownLatch(batchCount);
            this.responseLatencyNanos = new LongHistogram(config.histogramReservoir());
            this.requestAllocationBytesPerRecord = new LongHistogram(config.histogramReservoir());
            this.samples = samples;
            this.parity = parity;
        }

        void registerFlight(String batchId, Flight flight) {
            if (pending.putIfAbsent(batchId, flight) != null) {
                throw new IllegalStateException("duplicate outbound batch id " + batchId);
            }
            int active = activeInflight.incrementAndGet();
            peakInflight.accumulateAndGet(active, Math::max);
        }

        void abandonFlight(String batchId, Flight flight) {
            if (pending.remove(batchId, flight)) {
                activeInflight.decrementAndGet();
                inflight.release();
            }
        }

        void accept(TransformStreamResponse response, int streamIndex) {
            Flight flight = pending.remove(response.getBatchId());
            if (flight == null) {
                recordError("response had unknown batch id " + response.getBatchId());
                return;
            }
            activeInflight.decrementAndGet();
            long latency = Math.max(0, System.nanoTime() - flight.sentNanos());
            String identityViolation = flight.validate(response.getBatch().getResultsList());
            if (identityViolation != null) {
                recordError("response batch " + response.getBatchId() + " " + identityViolation);
                inflight.release();
                responses.countDown();
                return;
            }
            responseLatencyNanos.record(latency);
            long batchNumber = responseSequence.incrementAndGet();
            boolean captureSample = samples.shouldSample(batchNumber);
            int resultCount = 0;
            String outputHash = null;
            int sampledOutputBytes = 0;
            for (TransformResult result : response.getBatch().getResultsList()) {
                resultCount++;
                parity.write(response.getBatchId(), streamIndex, result);
                if (result.getStatus() == TransformStatus.OK) ok.increment();
                else if (result.getStatus() == TransformStatus.DLQ) dlq.increment();
                else failed.increment();
                outputBytes.add(result.getOutput().size());
                if (captureSample && outputHash == null && !result.getOutput().isEmpty()) {
                    outputHash = sha256(result.getOutput());
                    sampledOutputBytes = result.getOutput().size();
                }
            }
            responseRecords.add(resultCount);
            responseBatches.increment();
            samples.maybeWrite(batchNumber, response.getBatchId(), streamIndex, flight.recordCount(),
                resultCount, latency, outputHash, sampledOutputBytes);
            inflight.release();
            responses.countDown();
        }

        void recordError(String message) {
            boolean first = firstError.compareAndSet(null, message);
            stop.set(true);
            if (first) inflight.release(config.streams());
        }

        Observation observation(Instant started, Instant completed, boolean drained) {
            return new Observation(config, started, completed, drained, sentRecords.sum(), sentBatches.sum(),
                responseRecords.sum(), responseBatches.sum(), ok.sum(), dlq.sum(), failed.sum(), outputBytes.sum(),
                pending.size(), peakInflight.get(), firstError.get(), responseLatencyNanos.snapshotMicros(),
                requestAllocationBytesPerRecord.snapshotRaw());
        }
    }

    record Flight(long sentNanos, int firstRecord, int recordCount) {
        String validate(List<TransformResult> results) {
            if (results.size() != recordCount) {
                return "returned " + results.size() + " records; expected " + recordCount;
            }
            boolean[] observed = new boolean[recordCount];
            long endExclusive = (long) firstRecord + recordCount;
            for (TransformResult result : results) {
                String recordId = result.getRecordId();
                if (!recordId.startsWith("grpc-record-")) {
                    return "contained unexpected record id " + recordId;
                }
                long sequence;
                try {
                    sequence = Long.parseLong(recordId.substring("grpc-record-".length()));
                } catch (NumberFormatException exception) {
                    return "contained malformed record id " + recordId;
                }
                if (sequence < firstRecord || sequence >= endExclusive) {
                    return "contained out-of-range record id " + recordId;
                }
                int index = (int) (sequence - firstRecord);
                if (observed[index]) return "contained duplicate record id " + recordId;
                observed[index] = true;
            }
            return null;
        }
    }

    record Observation(Config config, Instant startedAt, Instant completedAt, boolean responseDrainCompleted,
                       long recordsSent, long batchesSent, long responseRecords, long responseBatches,
                       long ok, long dlq, long failed, long transformedOutputBytesObserved,
                       int outstandingBatches, int peakInflightBatches, String rpcObservation,
                       Map<String, Object> responseLatency, Map<String, Object> requestAllocationBytesPerRecord) {
        void requireComplete() {
            long expectedBatches = (long) Math.ceil(config.recordCount() / (double) config.batchSize());
            long accountedStatuses = ok + dlq + failed;
            List<String> violations = new ArrayList<>();
            if (!responseDrainCompleted) violations.add("response drain did not complete");
            if (rpcObservation != null) violations.add("RPC error: " + rpcObservation);
            if (recordsSent != config.recordCount()) {
                violations.add("records sent " + recordsSent + " != configured " + config.recordCount());
            }
            if (responseRecords != config.recordCount()) {
                violations.add("response records " + responseRecords + " != configured " + config.recordCount());
            }
            if (batchesSent != expectedBatches) {
                violations.add("batches sent " + batchesSent + " != expected " + expectedBatches);
            }
            if (responseBatches != expectedBatches) {
                violations.add("response batches " + responseBatches + " != expected " + expectedBatches);
            }
            if (outstandingBatches != 0) violations.add("outstanding batches " + outstandingBatches + " != 0");
            if (accountedStatuses != responseRecords) {
                violations.add("status total " + accountedStatuses + " != response records " + responseRecords);
            }
            if (!violations.isEmpty()) {
                throw new IllegalStateException("refusing to promote incomplete gRPC observation: "
                    + String.join("; ", violations));
            }
        }

        Map<String, Object> asMap() {
            double seconds = Math.max(0.001, Duration.between(startedAt, completedAt).toMillis() / 1000.0);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("schema", "flowplane.grpc-runtime-observation.v1");
            map.put("schemaVersion", 1);
            map.put("kind", "flowplane-benchmark-grpc-observation");
            map.put("campaignId", config.campaignId());
            map.put("runtimeType", "GRPC");
            map.put("runtimeId", config.expectedRuntimeId());
            map.put("mappingId", config.expectedMappingId());
            map.put("artifactId", config.expectedArtifactId());
            map.put("artifactHash", config.expectedArtifactHash());
            map.put("transport", config.expectedTransport());
            map.put("transportEvidence", config.transportEvidence());
            map.put("observationMode", "PERFORMANCE_MONITORING_ONLY");
            map.put("startedAt", startedAt.toString());
            map.put("completedAt", completedAt.toString());
            map.put("elapsedSeconds", seconds);
            map.put("configuredRecords", config.recordCount());
            map.put("recordsSent", recordsSent);
            map.put("batchesSent", batchesSent);
            map.put("responseRecords", responseRecords);
            map.put("responseBatches", responseBatches);
            map.put("okObserved", ok);
            map.put("dlqObserved", dlq);
            map.put("failedObserved", failed);
            map.put("responseDrainCompleted", responseDrainCompleted);
            map.put("outstandingBatches", outstandingBatches);
            map.put("rpcObservation", rpcObservation == null ? "none reported" : rpcObservation);
            map.put("achievedRecordsPerSecond", responseRecords / seconds);
            map.put("transformedOutputBytesObserved", transformedOutputBytesObserved);
            map.put("responseLatency", Map.of(
                "semantics", "source record send to runtime response; every record in a batch shares its batch latency",
                "unit", "microseconds",
                "values", responseLatency));
            map.put("clientRequestAllocation", Map.of(
                "semantics", "sender-thread request construction and gRPC submission allocation divided by records in batch",
                "unit", "bytes per record",
                "values", requestAllocationBytesPerRecord));
            map.put("streams", config.streams());
            map.put("batchSize", config.batchSize());
            map.put("maxInflightBatches", config.maxInflightBatches());
            map.put("peakInflightBatches", peakInflightBatches);
            map.put("outputHandling", "responses counted and discarded; bounded hash/size samples only; no downstream publisher exists");
            if (config.parityEvidencePath() != null) {
                map.put("parityEvidence", Map.of(
                    "path", config.parityEvidencePath().toString(),
                    "scope", "per-record runtime response contract including raw output for bounded parity/canary runs"));
            }
            map.put("jfr", Map.of("path", config.jfrFile().toString(), "scope", "full client JVM measured interval"));
            return map;
        }
    }

    static final class SampleWriter implements Closeable {
        private final BufferedWriter writer;
        private final int every;

        SampleWriter(Path path, int every) throws IOException {
            Files.createDirectories(path.getParent());
            this.writer = Files.newBufferedWriter(path, StandardCharsets.UTF_8);
            this.every = every;
        }

        synchronized void maybeWrite(long batchNumber, String batchId, int stream, int sentRecords,
                                     int responseRecords, long latencyNanos, String outputHash, int outputBytes) {
            if (!shouldSample(batchNumber)) return;
            try {
                Map<String, Object> sample = new LinkedHashMap<>();
                sample.put("batchNumber", batchNumber);
                sample.put("batchId", batchId);
                sample.put("stream", stream);
                sample.put("sentRecords", sentRecords);
                sample.put("responseRecords", responseRecords);
                sample.put("recordEndToEndLatencyMicros", latencyNanos / 1_000.0d);
                sample.put("outputSha256", outputHash);
                sample.put("outputBytes", outputBytes);
                writer.write(JSON.writeValueAsString(sample));
                writer.newLine();
            } catch (IOException exception) {
                throw new IllegalStateException("could not write bounded latency sample", exception);
            }
        }

        boolean shouldSample(long batchNumber) { return batchNumber == 1 || batchNumber % every == 0; }

        @Override public synchronized void close() throws IOException { writer.close(); }
    }

    static final class ParityWriter implements Closeable {
        private final BufferedWriter writer;

        ParityWriter() {
            writer = null;
        }

        ParityWriter(Path path) throws IOException {
            if (path == null) {
                writer = null;
                return;
            }
            Files.createDirectories(path.getParent());
            writer = Files.newBufferedWriter(path, StandardCharsets.UTF_8);
        }

        synchronized void write(String batchId, int stream, TransformResult result) {
            if (writer == null) return;
            try {
                Map<String, Object> evidence = new LinkedHashMap<>();
                evidence.put("batchId", batchId);
                evidence.put("stream", stream);
                evidence.put("recordId", result.getRecordId());
                evidence.put("status", result.getStatus().name());
                evidence.put("headers", result.getHeadersMap());
                evidence.put("outputBytes", result.getOutput().size());
                evidence.put("outputSha256", result.getOutput().isEmpty() ? null : sha256(result.getOutput()));
                evidence.put("outputBase64", result.getOutput().isEmpty()
                    ? null : Base64.getEncoder().encodeToString(result.getOutput().toByteArray()));
                if (result.hasError()) {
                    Map<String, Object> error = new LinkedHashMap<>();
                    error.put("code", result.getError().getCode());
                    error.put("message", result.getError().getMessage());
                    error.put("fieldPath", result.getError().getFieldPath());
                    error.put("stage", result.getError().getStage());
                    error.put("retryable", result.getError().getRetryable());
                    evidence.put("error", error);
                } else {
                    evidence.put("error", null);
                }
                if (result.hasDlq()) {
                    Map<String, Object> dlq = new LinkedHashMap<>();
                    dlq.put("reason", result.getDlq().getReason());
                    dlq.put("tenantId", result.getDlq().getTenantId());
                    dlq.put("runtimeId", result.getDlq().getRuntimeId());
                    dlq.put("mappingId", result.getDlq().getMappingId());
                    dlq.put("mappingVersion", result.getDlq().getMappingVersion());
                    dlq.put("artifactHash", result.getDlq().getArtifactHash());
                    dlq.put("originalRecordId", result.getDlq().getOriginalRecordId());
                    dlq.put("metadata", result.getDlq().getMetadataMap());
                    evidence.put("dlq", dlq);
                } else {
                    evidence.put("dlq", null);
                }
                writer.write(JSON_LINE.writeValueAsString(evidence));
                writer.newLine();
            } catch (IOException exception) {
                throw new IllegalStateException("could not write bounded per-record parity evidence", exception);
            }
        }

        @Override public synchronized void close() throws IOException {
            if (writer != null) writer.close();
        }
    }

    record Assignment(String tenantId, String runtimeId, String mappingId, String mappingVersion,
                      String artifactId, String artifactHash) {
        Map<String, Object> asMap() {
            return Map.of("tenantId", tenantId, "runtimeId", runtimeId, "mappingId", mappingId,
                "mappingVersion", mappingVersion, "artifactId", artifactId, "artifactHash", artifactHash);
        }
    }

    record Config(String campaignId, String host, int port, URI assignmentUrl, String expectedRuntimeId,
                  String expectedMappingId, String expectedArtifactId, String expectedArtifactHash,
                  String expectedTransport, String transportEvidence,
                  Path payloadJsonl, Path runDir, Path jfrFile,
                  int recordCount, int payloadVariants, int payloadBytes, int batchSize, int streams,
                  int maxInflightBatches, int targetRps, int maxInboundBytes, int histogramReservoir,
                  int sampleEveryBatches, int runTimeoutSeconds, int responseDrainSeconds,
                  Path parityEvidencePath) {
        static Config parse(String[] args) {
            Map<String, String> values = new HashMap<>();
            for (int index = 0; index < args.length; index += 2) {
                if (index + 1 >= args.length || !args[index].startsWith("--"))
                    throw new IllegalArgumentException("arguments must be --key value pairs");
                values.put(args[index].substring(2), args[index + 1]);
            }
            String[] target = values.getOrDefault("target", "127.0.0.1:19090").split(":", 2);
            Path runDir = Path.of(required(values, "run-dir")).toAbsolutePath().normalize();
            Config result = new Config(required(values, "campaign-id"), target[0], Integer.parseInt(target[1]),
                URI.create(values.getOrDefault("assignment-url", "http://127.0.0.1:18090/v1/runtime/assignments")),
                required(values, "expected-runtime-id"), required(values, "expected-mapping-id"),
                required(values, "expected-artifact-id"),
                required(values, "expected-artifact-hash"),
                values.getOrDefault("expected-transport", "GRPC_STREAM"),
                values.getOrDefault("transport-evidence", "verified setup/control-plane runtime evidence; assignment endpoint omits transport"),
                Path.of(required(values, "payload-jsonl")).toAbsolutePath().normalize(), runDir,
                Path.of(values.getOrDefault("jfr-file", runDir.resolve("grpc-client.jfr").toString())).toAbsolutePath().normalize(),
                integer(values, "record-count", 500_000), integer(values, "payload-variants", 100),
                integer(values, "payload-bytes", 102_400), integer(values, "batch-size", 10),
                integer(values, "streams", 4), integer(values, "max-inflight-batches", 128),
                integer(values, "target-rps", 0), integer(values, "max-inbound-bytes", 67_108_864),
                integer(values, "histogram-reservoir", 65_536), integer(values, "sample-every-batches", 100),
                integer(values, "run-timeout-seconds", 7_200), integer(values, "response-drain-seconds", 120),
                values.containsKey("parity-evidence-path")
                    ? Path.of(values.get("parity-evidence-path")).toAbsolutePath().normalize()
                    : null);
            result.validate();
            return result;
        }

        private void validate() {
            if (recordCount < 1 || batchSize < 1 || streams < 1 || maxInflightBatches < streams)
                throw new IllegalArgumentException("record-count/batch-size/streams must be positive and max-inflight-batches >= streams");
            if (payloadVariants < 1 || payloadBytes < 1 || histogramReservoir < 1 || sampleEveryBatches < 1)
                throw new IllegalArgumentException("payload and observation limits must be positive");
            if (parityEvidencePath != null && recordCount > 1_000)
                throw new IllegalArgumentException("parity-evidence-path is bounded to at most 1000 records");
        }

        private static int integer(Map<String, String> values, String key, int fallback) {
            return Integer.parseInt(values.getOrDefault(key, Integer.toString(fallback)));
        }

        private static String required(Map<String, String> values, String key) {
            String value = values.get(key);
            if (value == null || value.isBlank()) throw new IllegalArgumentException("missing --" + key);
            return value;
        }
    }

    private static Assignment fetchAssignment(Config config) throws IOException, InterruptedException {
        HttpResponse<String> response = HTTP.send(HttpRequest.newBuilder(config.assignmentUrl()).timeout(Duration.ofSeconds(10)).GET().build(),
            HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw new IllegalStateException("assignment fetch returned HTTP " + response.statusCode());
        JsonNode assignments = JSON.readTree(response.body());
        if (!assignments.isArray() || assignments.isEmpty()) throw new IllegalStateException("no runtime assignment returned");
        return selectAssignment(assignments, config);
    }

    static Assignment selectAssignment(JsonNode assignments, Config config) {
        for (JsonNode item : assignments) {
            if (config.expectedRuntimeId().equals(item.path("runtimeId").asText())
                && config.expectedMappingId().equals(item.path("mappingId").asText())
                && config.expectedArtifactId().equals(item.path("artifactId").asText())
                && config.expectedArtifactHash().equals(item.path("artifactHash").asText())) {
                String version = item.hasNonNull("mappingVersion")
                    ? item.path("mappingVersion").asText() : item.path("version").asText();
                return new Assignment(item.path("tenantId").asText(), item.path("runtimeId").asText(),
                    item.path("mappingId").asText(), version, item.path("artifactId").asText(),
                    item.path("artifactHash").asText());
            }
        }
        throw new IllegalStateException("no assignment exactly matched expected runtime, mapping, artifact id, and artifact hash");
    }

    private static Recording startJfr(Path destination) throws Exception {
        Files.createDirectories(destination.toAbsolutePath().getParent());
        Recording recording = new Recording(Configuration.getConfiguration("profile"));
        recording.setName("flowplane-isolated-grpc-client");
        recording.setToDisk(true);
        recording.enable("jdk.ObjectAllocationSample").withPeriod(Duration.ofMillis(20));
        recording.enable("jdk.ObjectAllocationInNewTLAB").withThreshold(Duration.ZERO);
        recording.enable("jdk.ObjectAllocationOutsideTLAB").withThreshold(Duration.ZERO);
        recording.start();
        return recording;
    }

    private static long allocatedBytes() {
        if (ManagementFactory.getThreadMXBean() instanceof com.sun.management.ThreadMXBean bean
            && bean.isThreadAllocatedMemorySupported()) {
            if (!bean.isThreadAllocatedMemoryEnabled()) bean.setThreadAllocatedMemoryEnabled(true);
            return bean.getThreadAllocatedBytes(Thread.currentThread().getId());
        }
        return -1;
    }

    private static void writeManifest(Config config, Assignment assignment, PayloadSet payloads) throws IOException {
        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("schema", "flowplane.grpc-runtime-source-manifest.v1");
        manifest.put("schemaVersion", 1);
        manifest.put("campaignId", config.campaignId());
        manifest.put("runtimeType", "GRPC");
        manifest.put("runtimeId", config.expectedRuntimeId());
        manifest.put("mappingId", config.expectedMappingId());
        manifest.put("artifactId", config.expectedArtifactId());
        manifest.put("artifactHash", config.expectedArtifactHash());
        manifest.put("createdAt", Instant.now().toString());
        manifest.put("assignment", assignment.asMap());
        manifest.put("sourcePayloadFile", config.payloadJsonl().toString());
        manifest.put("payloadVariants", payloads.size());
        manifest.put("payloadBytes", config.payloadBytes());
        manifest.put("payloadSha256", payloads.hashes());
        manifest.put("recordCount", config.recordCount());
        manifest.put("sequenceRule", "payloadIndex = recordSequence % payloadVariants");
        manifest.put("transport", config.expectedTransport());
        manifest.put("transportEvidence", config.transportEvidence());
        manifest.put("downstreamInsertion", "none; transformed responses are never republished");
        manifest.put("parityEvidencePath", config.parityEvidencePath() == null
            ? null : config.parityEvidencePath().toString());
        JSON.writeValue(config.runDir().resolve("grpc-source-manifest.json").toFile(), manifest);
    }

    static void assertFreshOutputDirectory(Config config) {
        for (String name : List.of("grpc-client-observation.json", "grpc-client-observation.partial.json",
                                   "grpc-client.jfr", "latency-samples.jsonl", "grpc-source-manifest.json")) {
            Path candidate = config.runDir().resolve(name);
            if (Files.exists(candidate)) {
                throw new IllegalStateException("refusing to overwrite existing measured evidence: " + candidate);
            }
        }
        if (Files.exists(config.jfrFile())) {
            throw new IllegalStateException("refusing to overwrite existing measured evidence: " + config.jfrFile());
        }
        if (config.parityEvidencePath() != null && Files.exists(config.parityEvidencePath())) {
            throw new IllegalStateException("refusing to overwrite existing parity evidence: " + config.parityEvidencePath());
        }
    }

    private static String sha256(com.google.protobuf.ByteString bytes) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (var input = bytes.newInput()) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = input.read(buffer)) >= 0) {
                    if (read > 0) digest.update(buffer, 0, read);
                }
            }
            return "sha256:" + HexFormat.of().formatHex(digest.digest());
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }
}
