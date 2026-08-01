# Operations and transformations

Flowplane changes one JSON record into another JSON record.

A mapping can copy fields, clean text, calculate values, reshape arrays, validate data, and protect sensitive information. The same mapping can run through Kafka, Flink, Pulsar, HTTP, or another supported runtime.

In this guide:

- an **operation** is one action, such as copying or masking a field; and
- a **transformation** is the complete input-to-output change made by a mapping.

Flowplane mappings are stateless: each record is transformed independently. The host system remains responsible for transport, retries, acknowledgements, ordering, checkpoints, and destinations.

## Start with a simple example

Input:

```json
{
  "device": {
    "id": "42",
    "type": "gateway",
    "status": "ok"
  },
  "temperatureC": 20
}
```

Mapping:

```yaml
output: FLAT_OBJECT

fields:
  device_id: $.device.id

  status:
    path: $.device.status
    case_convert: upper

  label:
    valueExpr:
      function:
        name: concat
        args:
          - path: $.device.type
          - const: "-"
          - path: $.device.id

  temperature_f:
    expression: "$.temperatureC * 1.8 + 32"
    round:
      scale: 2
```

Output:

```json
{
  "device_id": "42",
  "status": "OK",
  "label": "gateway-42",
  "temperature_f": 68.00
}
```

This example performs four operations: copy, uppercase, join, and calculate.

The runnable files are in the [operations starter example](../examples/operations/README.md).

This page is the readable guide. For every accepted operation and option, including less common policies and error formats, use the [complete operations reference](operations-reference.md).

## Copy or create values

| What you want | Mapping example | Meaning |
|---|---|---|
| Copy a field | `order_id: $.order.id` | Read the value at the JSON path |
| Use another path if missing | `fallback: [$.account.region]` | Try the fallback after the main path |
| Add a fixed value | `constant: production` | Always return `production` |
| Add a literal | `value: production` | Another way to return a fixed value |
| Read runtime metadata | `metadata: requestId` | Read a value supplied by the runtime |
| Read a message header | `header: x-trace-id` | Read a transport header |
| Generate an ID | `generate: uuid` | Create a new UUID |
| Add the current time | `generate: now` | Create an ISO-8601 timestamp |

`path`, `direct`, and `source` can all select input data. Prefer `path` because it is easiest to understand.

Example with a fallback:

```yaml
fields:
  region:
    path: $.customer.region
    fallback:
      - $.account.region
      - $.defaultRegion
```

Flowplane uses the first available value.

## Clean and format text

| Operation | Input | Result |
|---|---|---|
| `case_convert: upper` | `ready` | `READY` |
| `case_convert: lower` | `READY` | `ready` |
| `normalize_string: true` | `  Fan   speed  ` | `Fan speed` |
| `template: "status-${value}"` | `OK` | `status-OK` |
| `substring: {start: 0, end: 2}` | `GW-0042` | `GW` |
| `split: {by: "|"}` | `a|b|c` | `[a, b, c]` |
| `regex_match` | `OK` | keeps `OK` when it matches; adds a field error when it does not |
| `regex_extract` | `GW-0042` | the matching text or capture group |
| `regex_replace` | `fw-v2.7.1` | `v2.7.1` after removing `fw-` |

Example:

```yaml
fields:
  clean_message:
    path: $.message
    normalize_string: true

  serial_family:
    path: $.serial
    regex_extract: "^(GW)-.*"

  firmware_version:
    path: $.firmware
    regex_replace: "^fw-"
    replacement: ""
```

## Join values with functions

```yaml
fields:
  device_label:
    valueExpr:
      function:
        name: concat
        args:
          - path: $.device.type
          - const: "-"
          - path: $.device.id
```

For type `gateway` and ID `42`, the result is `gateway-42`.

| Function | What it does |
|---|---|
| `concat` | Joins values into one string |
| `template` | Builds text from multiple values |
| `upper` / `lower` | Changes letter case |
| `trim` | Removes spaces from both ends |
| `substring` | Returns part of a string |
| `split` | Splits text into a list |
| `round` | Rounds a number to a selected scale |
| `now` | Returns the current time |
| `uuid` | Creates a UUID |
| `hash` | Creates a SHA-256 digest |

`function`, `func`, and `fn` are accepted aliases. Prefer `function` for readability.

## Choose a value

### Use the first useful value

```yaml
fields:
  email:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - path: $.primaryEmail
          - path: $.backupEmail
          - const: unknown@example.com
```

Flowplane checks the candidates in order and returns the first non-empty value.

Coalesce modes are:

- `FIRST_NON_MISSING`: skip paths that do not exist;
- `FIRST_NON_NULL`: also skip null values;
- `FIRST_NON_EMPTY`: also skip empty values; and
- `FIRST_VALID`: return the first usable candidate.

### Use conditions

```yaml
fields:
  route:
    valueExpr:
      case:
        branches:
          - when:
              path: $.risk
              operator: EQ
              value: HIGH
            then:
              const: page-oncall
        else:
          const: observe
```

When `risk` is `HIGH`, the output is `page-oncall`. Otherwise it is `observe`.

Supported conditions:

- equality: `EQ`, `NE`;
- numeric comparison: `GT`, `GTE`, `LT`, `LTE`;
- presence: `EXISTS`, `MISSING`, `IS_NULL`, `NOT_NULL`;
- empty values: `IS_EMPTY`, `NOT_EMPTY`;
- text and collections: `IN`, `CONTAINS`, `STARTS_WITH`, `ENDS_WITH`; and
- regular expressions: `REGEX_MATCH`.

Use `all`/`and` when every condition must match. Use `any`/`or` when one match is enough.

### Use a lookup table

```yaml
lookups:
  statusCodes:
    OK: observe
    WARN: investigate
    FAIL: dispatch

fields:
  action:
    path: $.status
    lookup:
      dictionary: statusCodes
      onMiss: DEFAULT
      defaultValue: unknown
```

`WARN` becomes `investigate`. An unknown code becomes `unknown`.

Lookup miss actions are `KEEP_ORIGINAL`, `DEFAULT`, `NULL`, `SKIP_FIELD`, and `ERROR`. Lookups can also ignore case, trim input, and select one property from an object-valued result.

## Calculate values

```yaml
fields:
  total:
    expression: "$.price * $.quantity"

  is_adult:
    expression: "$.age >= 18"

  temperature_f:
    expression: "$.temperatureC * 1.8 + 32"
    round:
      scale: 2
```

Expressions support `+`, `-`, `*`, `/`, `>`, `>=`, `<`, `<=`, `==`, and `!=`.

Arithmetic is evaluated from left to right. Split complex calculations into separate fields when normal operator precedence matters. `arithmetic` is an alias for an arithmetic `expression`.

## Convert data types

```yaml
fields:
  quantity:
    path: $.quantity
    cast: int

  amount:
    path: $.amount
    cast: decimal
    decimalScale: 2
    decimalScalePolicy: ROUND
```

| Type | Result |
|---|---|
| `STRING` | Text |
| `INT` / `INTEGER` | 32-bit whole number |
| `LONG` | 64-bit whole number |
| `DOUBLE` | Floating-point number |
| `DECIMAL` | Precise decimal number |
| `BOOLEAN` | `true` or `false` |
| `TIMESTAMP` | Epoch milliseconds |
| `DATE` | Calendar date |
| `TIME` | Time of day |
| `JSON` | Parsed JSON value |
| `OBJECT` | JSON object |
| `ARRAY` | JSON array |

Use `date_format` for non-standard date or time text. Decimal scale policies are `FAIL`, `ROUND`, and `TRUNCATE`. Numeric overflow policies are `ERROR`, `CLAMP`, and `DEFAULT`.

## Work with arrays

For this input:

```json
{
  "signals": [
    { "name": "cpu", "value": 82 },
    { "name": "mem", "value": 67 },
    { "name": "disk", "value": 91 }
  ]
}
```

Flowplane supports these selection modes:

| Mode | Result for signal names |
|---|---|
| `FIRST` | `cpu` |
| `LAST` | `disk` |
| `INDEX` with index `1` | `mem` |
| `ONLY` | the value only when exactly one exists |
| `FILTER_FIRST` | first value matching a path filter |
| `FILTER_ALL` | all values matching a path filter |
| `COUNT` | `3` |
| `COLLECT` | `[cpu, mem, disk]` |
| `JOIN` | `cpu|mem|disk` |

Example:

```yaml
fields:
  first_signal:
    path: $.signals[*].name
    array_mode: FIRST

  high_signals:
    path: $.signals[?(@.value >= 80)].name
    array_mode: FILTER_ALL

  signal_total:
    path: $.signals[*].value
    aggregate: sum
```

This produces `cpu`, `[cpu, disk]`, and `240`.

Other array operations:

| Operation | What it does |
|---|---|
| `filter` | Keeps items matching a condition such as `item.value >= 80` |
| `map` | Renames or selects properties in every item |
| `flatten` | Converts nested lists into one list |
| `distinct` | Removes duplicate values |
| `aggregate: count` | Counts values |
| `aggregate: sum` | Adds numeric values |
| `aggregate: min` / `max` | Returns the smallest or largest value |

## Build objects

Create a new object:

```yaml
fields:
  customer:
    object:
      id: $.customerId
      email: $.customerEmail
```

Merge existing objects:

```yaml
fields:
  profile:
    merge:
      - $.profile.basic
      - $.profile.preferences
```

Create nested output by using dotted field names with `output: OBJECT`:

```yaml
output: OBJECT
fields:
  customer.id: $.customerId
  customer.email: $.customerEmail
```

## Validate and handle bad values

```yaml
fields:
  event_id:
    path: $.event.id
    required: true
    validate: "^evt-"

  age:
    path: $.age
    cast: int
    validate:
      min: 0
      max: 120
    on_error:
      action: SET_DEFAULT
      value: 0
```

Validation supports `required`, `pattern`, `min`, `max`, and `one_of`.

When one field fails, `on_error` can:

- `SKIP_FIELD`: omit the field;
- `SET_NULL`: return null; or
- `SET_DEFAULT`: return a configured value.

Field policies handle unexpected input:

| Problem | Setting | Choices |
|---|---|---|
| Missing path | `onMissing` | `NULL`, `SKIP_FIELD`, `ERROR` |
| Null value | `onNull` | `ALLOW`, `DEFAULT`, `ERROR` |
| Array instead of a scalar | `onArray` | `USE_PICK`, `JSON_STRING`, `ERROR` |
| Object instead of a scalar | `onObject` | `NATIVE`, `JSON_STRING`, `ERROR` |
| Incorrect type | `onTypeMismatch` | `COERCE`, `STRINGIFY`, `DEFAULT`, `ERROR` |
| Number is too large | `onOverflow` | `ERROR`, `CLAMP`, `DEFAULT` |

`default` or `defaultValue` supplies a fallback value. Use `strict: true` for strict field handling.

## Protect sensitive values

| Operation | What it does |
|---|---|
| `mask: last4` | Hides everything except the final four characters |
| `sensitive: true` | Applies protected display behavior |
| `hash: sha256` | Creates a one-way, repeatable digest |
| `redact: true` | Replaces the value with null |
| `encrypt` | Creates AES-GCM ciphertext using a runtime key reference |
| `decrypt` | Restores ciphertext using the same key reference |

Example:

```yaml
fields:
  masked_token:
    path: $.token
    mask: last4

  customer_hash:
    path: $.customerId
    hash: sha256

  encrypted_secret:
    path: $.secret
    encrypt:
      key_ref: payments
```

`tok-1234567890` becomes `**********7890`. Encryption keys come from secure runtime configuration and are not stored in the mapping.

## Choose the output format

| Output shape | Meaning |
|---|---|
| `OBJECT` | Nested JSON object |
| `FLAT_OBJECT` | Flat JSON object |
| `JSON_STRING` | Serialized JSON text |
| `PRIMITIVE` | One output value |
| `BYTES` | Serialized bytes |

Host output options can keep objects and arrays as native JSON, convert them to JSON strings, or reject them. Host options can also keep field names unchanged or convert them to snake case or camel case.

## Handle a failed record

Field-level `on_error` handles one field. Mapping-level policies tell the host what to do with the whole record.

```yaml
errorPolicy:
  onTransformationError: ROUTE_TO_DLQ
  onValidationFailure: SKIP_RECORD
  onTypeMismatch: REDACT_AND_PROCEED
```

Record actions:

- `FAIL_PIPELINE`: report failure and stop;
- `SKIP_RECORD`: do not emit the record;
- `ROUTE_TO_DLQ`: send it to a dead-letter destination; and
- `REDACT_AND_PROCEED`: remove sensitive error content and continue.

Error output can use `ROUTE_TO_DLQ`, `EMIT_TO_TOPIC`, `FAIL_PIPELINE`, `DROP`, or `RETRY`. Supported formats are `ENVELOPE`, `FIELD_ERRORS`, `COMPACT`, `CLOUD_EVENTS`, and `CUSTOM`.

The host performs the actual retry, topic write, acknowledgement, or dead-letter write.

## What is outside the mapping

Flowplane mappings intentionally do not implement joins between records, time windows, sessions, state stores, timers, watermarks, broker delivery, retries, acknowledgements, checkpoints, backpressure, or ordering.

Those responsibilities belong to Kafka, Flink, Pulsar, Spark, NiFi, or another host. Flowplane rejects stateful mapping keys instead of pretending to support them.

## Verification

The documented operation surface was checked on 2026-07-22 with 25 compiler/runtime contract tests and one exact public-fixture comparison. All 26 checks passed.

See the [verification record](../examples/operations/verification.json) for the runtime revision, result, and fixture hashes. All examples use synthetic data.

Continue to the [complete operations reference](operations-reference.md) for an explanation of every supported operation and option.
