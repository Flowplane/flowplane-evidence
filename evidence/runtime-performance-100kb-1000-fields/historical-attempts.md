# Historical and interrupted attempts

The headline metrics in this evidence family exclude earlier interrupted or
superseded attempts.

| Attempt | Classification | Preserved reason |
|---|---|---|
| `grpc-20260730-1908` | `INCOMPLETE` | Superseded before the final measured gRPC campaign |
| `grpc-20260730-2313` | `INCOMPLETE` | Interrupted before the final `grpc-20260730-2317` evidence set |
| `custom-java-20260731-0935` | `PRESERVED_FAILURE` | First custom campaign failed before the completed replacement run |
| Custom controller exit-code artifact | Operational limitation | Publisher manifest and Kafka counts showed completion, but the controller failed to persist the completed publisher exit code |

The completed custom run was recovered without republishing. Its window starts
at the persisted broker-JFR start time, uses the producer-JFR host timestamp as
publish end, and uses runtime container completion as drain end. This recovered
boundary is disclosed in the comparison and is not represented as a directly
recorded controller window.

Exploratory HTTP concurrency trials are intentionally not promoted into claims.
The four-thread trials measured 139.666, 143.844, and 143.083 records/s; a single
eight-thread trial was insufficient for a qualified concurrency conclusion.
