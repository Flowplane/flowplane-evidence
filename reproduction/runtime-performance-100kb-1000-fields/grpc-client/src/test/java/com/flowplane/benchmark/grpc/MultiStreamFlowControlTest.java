package com.flowplane.benchmark.grpc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.flowplane.runtime.v1.FlowPlaneTransformServiceGrpc;
import com.flowplane.runtime.v1.TransformBatchResponse;
import com.flowplane.runtime.v1.TransformResult;
import com.flowplane.runtime.v1.TransformStatus;
import com.flowplane.runtime.v1.TransformStreamRequest;
import com.flowplane.runtime.v1.TransformStreamResponse;
import com.google.protobuf.ByteString;
import io.grpc.ManagedChannel;
import io.grpc.Server;
import io.grpc.inprocess.InProcessChannelBuilder;
import io.grpc.inprocess.InProcessServerBuilder;
import io.grpc.stub.StreamObserver;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class MultiStreamFlowControlTest {
    @Test void firstRpcErrorReleasesBlockedSenders(@TempDir Path temporary) throws Exception {
        try (GrpcObservationClient.SampleWriter writer =
                 new GrpcObservationClient.SampleWriter(temporary.resolve("samples.jsonl"), 100)) {
            GrpcObservationClient.RunState state =
                new GrpcObservationClient.RunState(config(temporary), 8, writer);
            state.inflight.acquire(8);

            state.recordError("forced stream error");

            assertTrue(state.stop.get());
            assertTrue(state.inflight.tryAcquire(8, 1, TimeUnit.SECONDS));
        }
    }

    @Test void eightStreamsStartAndDrainWithAutomaticInboundFlowControl(@TempDir Path temporary) throws Exception {
        String serverName = InProcessServerBuilder.generateName();
        Server server = InProcessServerBuilder.forName(serverName).directExecutor()
            .addService(new EchoService()).build().start();
        ManagedChannel channel = InProcessChannelBuilder.forName(serverName).directExecutor().build();
        ExecutorService senders = Executors.newFixedThreadPool(8);
        Path samples = temporary.resolve("samples.jsonl");
        try (GrpcObservationClient.SampleWriter writer = new GrpcObservationClient.SampleWriter(samples, 100)) {
            GrpcObservationClient.Config config = config(temporary);
            GrpcObservationClient.RunState state = new GrpcObservationClient.RunState(config, 8, writer);
            var stub = FlowPlaneTransformServiceGrpc.newStub(channel);
            List<GrpcObservationClient.StreamSession> sessions = new ArrayList<>();
            for (int index = 0; index < 8; index++) {
                sessions.add(new GrpcObservationClient.StreamSession(index, stub, state));
            }

            List<Future<?>> sends = new ArrayList<>();
            for (int index = 0; index < 8; index++) {
                int stream = index;
                sends.add(senders.submit(() -> {
                    state.inflight.acquireUninterruptibly();
                    String batchId = "batch-" + stream;
                    state.registerFlight(batchId, new GrpcObservationClient.Flight(System.nanoTime(), stream, 1));
                    try {
                        sessions.get(stream).send(TransformStreamRequest.newBuilder()
                            .setBatchId(batchId).build());
                    } catch (InterruptedException exception) {
                        Thread.currentThread().interrupt();
                        throw new IllegalStateException(exception);
                    }
                }));
            }
            for (Future<?> send : sends) send.get(5, TimeUnit.SECONDS);

            assertTrue(state.responses.await(5, TimeUnit.SECONDS));
            assertNull(state.firstError.get());
            assertEquals(8L, state.responseBatches.sum());
            sessions.forEach(GrpcObservationClient.StreamSession::complete);
            for (GrpcObservationClient.StreamSession session : sessions) {
                assertTrue(session.awaitClosed(5, TimeUnit.SECONDS));
            }
        } finally {
            senders.shutdownNow();
            channel.shutdownNow();
            server.shutdownNow();
        }
    }

    private static GrpcObservationClient.Config config(Path temporary) {
        return GrpcObservationClient.Config.parse(new String[] {
            "--payload-jsonl", temporary.resolve("payloads.jsonl").toString(),
            "--run-dir", temporary.toString(), "--record-count", "8", "--batch-size", "1",
            "--streams", "8", "--max-inflight-batches", "8",
            "--campaign-id", "grpc-test", "--expected-runtime-id", "runtime-test",
            "--expected-mapping-id", "mapping-test", "--expected-artifact-id", "artifact-test",
            "--expected-artifact-hash", "sha256:test"
        });
    }

    private static final class EchoService extends FlowPlaneTransformServiceGrpc.FlowPlaneTransformServiceImplBase {
        @Override public StreamObserver<TransformStreamRequest> transformStream(
                StreamObserver<TransformStreamResponse> responses) {
            return new StreamObserver<>() {
                @Override public void onNext(TransformStreamRequest request) {
                    responses.onNext(TransformStreamResponse.newBuilder()
                        .setBatchId(request.getBatchId())
                        .setBatch(TransformBatchResponse.newBuilder().addResults(
                            TransformResult.newBuilder().setRecordId(
                                "grpc-record-" + request.getBatchId().substring("batch-".length()))
                                .setStatus(TransformStatus.OK)
                                .setOutput(ByteString.copyFromUtf8("observed"))))
                        .build());
                }

                @Override public void onError(Throwable throwable) {}

                @Override public void onCompleted() { responses.onCompleted(); }
            };
        }
    }
}
