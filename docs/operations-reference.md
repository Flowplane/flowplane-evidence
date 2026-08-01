# Complete operations reference

This reference explains every stateless operation and option supported by the current Flowplane mapping runtime. It is intentionally complete. For a shorter introduction with larger examples, start with [Operations and transformations](operations-and-transformations.md).

Examples use this general shape:

```yaml
output: FLAT_OBJECT
fields:
  output_field:
    path: $.inputField
    operation: option
```

## Field definitions and value sources

### Short path

```yaml
fields:
  customer_id: $.customer.id
```

Copies the value at `$.customer.id` into `customer_id`. This is the shortest form for a direct copy.

### `path`

```yaml
customer_id:
  path: $.customer.id
```

Selects a value with JSONPath. Use the expanded form when the field also needs a transform, validation rule, policy, or fallback.

### `direct`

```yaml
customer_id:
  direct: $.customer.id
```

An alias for `path`. It produces the same value. Prefer `path` in new mappings for consistency.

### `source`

```yaml
customer_id:
  source: $.customer.id
```

Another alias for `path`. It is useful when importing mappings that call an input location a source.

### `fallback`

```yaml
region:
  path: $.customer.region
  fallback:
    - $.account.region
    - $.defaultRegion
```

Tries the main path first, then each fallback in order. Flowplane returns the first available value.

### `constant`

```yaml
environment:
  constant: production
```

Returns the configured value for every record. It does not read the input.

### `value`

```yaml
environment:
  value: production
```

Returns a literal value. It can also hold arrays or objects. For a simple fixed scalar, `constant` and `value` have the same practical result.

### `metadata`

```yaml
request_id:
  metadata: requestId
```

Reads a metadata value supplied by the host runtime. If the host did not supply that key, normal missing/default policies apply.

### `header`

```yaml
trace_id:
  header: x-trace-id
```

Reads a message or request header supplied by the host integration. It does not read a field from the JSON body.

### `generate: uuid`

```yaml
event_id:
  generate: uuid
```

Creates a new UUID for each transformation. The result is nondeterministic.

### `generate: now`

```yaml
processed_at:
  generate: now
```

Returns the current time as an ISO-8601 instant. The result changes on every run.

### `valueExpr`

```yaml
label:
  valueExpr:
    function:
      name: upper
      args:
        - path: $.status
```

Defines a value using a function, coalesce, case expression, lookup, path, constant, or context value.

### `context`

```yaml
tenant:
  valueExpr:
    context: tenantId
```

Reads a value from the transformation context. `metadata.name` reads a metadata key and `header.name` reads a header key. An unprefixed key checks runtime metadata first and then headers.

### `expression`, `expr`, and `arithmetic`

```yaml
total:
  expression: "$.price * $.quantity"
```

Evaluates a simple numeric or comparison expression. `expr` is a short alias. `arithmetic` is an alias intended for numeric expressions.

## Coalesce operations

Coalesce checks candidates from top to bottom and returns the first candidate accepted by its mode.

```yaml
email:
  valueExpr:
    coalesce:
      mode: FIRST_NON_EMPTY
      candidates:
        - path: $.primaryEmail
        - path: $.backupEmail
        - const: unknown@example.com
```

| Mode | Explanation |
|---|---|
| `FIRST_NON_MISSING` | Returns the first candidate whose path exists. A present null or empty value can be returned. |
| `FIRST_NON_NULL` | Skips missing and null candidates. An empty string, array, or object can still be returned. |
| `FIRST_NON_EMPTY` | Skips missing, null, empty-string, empty-array, and empty-object values. |
| `FIRST_VALID` | Returns the first candidate that the runtime considers usable after candidate evaluation. |

Candidate forms include `path`, `const`, `context`, and their typed `PATH` / `CONST` forms.

## Case conditions and predicates

A case expression checks branches in order. The first matching branch supplies the output. `else` supplies the value when no branch matches.

```yaml
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

### Predicate operators

| Operator | Explanation | Simple example |
|---|---|---|
| `EXISTS` | True when the path exists, even if its value is null. | Does `$.email` exist? |
| `MISSING` | True when the path does not exist. | Is `$.email` absent? |
| `IS_NULL` | True when the selected value is explicitly null. | Is `$.email` null? |
| `NOT_NULL` | True when the selected value is not null. | Does `$.email` contain a non-null value? |
| `IS_EMPTY` | True for an empty string, array, or object. | Is `$.tags` empty? |
| `NOT_EMPTY` | True when the value is not empty. | Does `$.name` contain text? |
| `EQ` | True when the values are equal. | `status EQ OK` |
| `NE` | True when the values are different. | `status NE FAIL` |
| `GT` | True when the left value is greater than the comparison value. | `score GT 80` |
| `GTE` | True when the left value is greater than or equal to the comparison value. | `score GTE 80` |
| `LT` | True when the left value is less than the comparison value. | `temperature LT 0` |
| `LTE` | True when the left value is less than or equal to the comparison value. | `attempts LTE 3` |
| `IN` | True when the value appears in the configured list. | `status IN [OK, WARN]` |
| `REGEX_MATCH` | True when text matches the regular expression. | `code REGEX_MATCH ^A-` |
| `STARTS_WITH` | True when text begins with the configured text. | `code STARTS_WITH A-` |
| `ENDS_WITH` | True when text ends with the configured text. | `file ENDS_WITH .json` |
| `CONTAINS` | True when text or a collection contains the configured value. | `message CONTAINS error` |

### Predicate composition

| Key | Explanation |
|---|---|
| `all` | Every nested condition must be true. |
| `and` | Alias for `all`. |
| `any` | At least one nested condition must be true. |
| `or` | Alias for `any`. |

## Lookup operations

Lookups replace an input key with a value from a named dictionary.

```yaml
lookups:
  statusCodes:
    OK: observe
    WARN: investigate

fields:
  action:
    path: $.status
    lookup:
      dictionary: statusCodes
```

### Lookup options

| Option | Explanation |
|---|---|
| `dictionary` | Names the lookup dictionary. |
| `version` | Identifies a requested dictionary version when a version-aware provider is used. |
| `path` | Reads the lookup key from an input path inside a value expression. |
| `key` | Defines the lookup key explicitly, commonly as another path expression. |
| `resultField` | Selects one property when the dictionary result is an object. |
| `onMiss` | Chooses what happens when the key is absent. |
| `defaultValue` | Supplies the value used by `onMiss: DEFAULT`. |
| `caseInsensitive` | Matches text keys without requiring the same letter case. |
| `trimInput` | Removes leading and trailing spaces before matching the key. |

### Lookup miss actions

| Action | Explanation |
|---|---|
| `KEEP_ORIGINAL` | Returns the original lookup key. |
| `DEFAULT` | Returns `defaultValue`. |
| `NULL` | Returns null. |
| `SKIP_FIELD` | Omits the output field. |
| `ERROR` | Adds a field error. |

## Value-expression functions

Functions may be declared with `function`, `func`, or `fn`. Prefer `function`.

| Function | Arguments | Explanation | Example result |
|---|---|---|---|
| `concat` | Any number of values | Converts each argument to text and joins them without a separator. | `Ada`, ` `, `Lovelace` → `Ada Lovelace` |
| `template` | Any number of values | Joins values into formatted text. | `id=`, `42` → `id=42` |
| `upper` | One value | Converts text to uppercase. | `ready` → `READY` |
| `lower` | One value | Converts text to lowercase. | `READY` → `ready` |
| `trim` | One value | Removes leading and trailing whitespace. | `  ready  ` → `ready` |
| `substring` | Text, start, optional end | Returns the selected character range. Indexes are clamped to valid bounds. | `stream`, `1`, `5` → `trea` |
| `split` | Text and delimiter | Splits text using the literal delimiter. | `a,b,c`, `,` → `[a,b,c]` |
| `round` | Number and scale | Rounds with half-up behavior. | `12.345`, `2` → `12.35` |
| `now` | No arguments | Returns the current ISO-8601 instant. | current time |
| `uuid` | No arguments | Returns a new UUID. | new UUID string |
| `hash` | One value | Returns the SHA-256 digest of the value. | hexadecimal digest |

## Text transforms

### `case_convert: upper`

Converts the selected value to uppercase text. `Ready` becomes `READY`.

### `case_convert: lower`

Converts the selected value to lowercase text. `Ready` becomes `ready`.

### `normalize_string: true`

Trims text and replaces repeated whitespace with one normal space. `  Fan   speed  ` becomes `Fan speed`.

### `template`

```yaml
status_label:
  path: $.status
  template: "status-${value}"
```

Replaces `${value}` with the field value. `OK` becomes `status-OK`.

### `substring`

```yaml
serial_prefix:
  path: $.serial
  substring:
    start: 0
    end: 2
```

Returns characters from `start` up to, but not including, `end`. The end value is optional.

### `split`

```yaml
labels:
  path: $.labels
  split:
    by: "|"
```

Splits text using a literal delimiter. `a|b|c` becomes `[a,b,c]`.

### `regex_match`

```yaml
validated_status:
  path: $.status
  regex_match: "^(OK|WARN|FAIL)$"
```

Validates the selected value. When the pattern matches, Flowplane keeps the original value. When it does not match, Flowplane adds a `REGEX_FAILED` field error. It does not convert the field to a Boolean.

### `regex_extract`

```yaml
serial_family:
  path: $.serial
  regex_extract: "^(GW)-.*"
```

Returns capture group 1 when the pattern contains a capture group. Otherwise it returns the whole match. It returns null when nothing matches.

### `regex_replace` and `replacement`

```yaml
firmware:
  path: $.firmware
  regex_replace: "^fw-"
  replacement: ""
```

Replaces regex matches with `replacement`. The example removes the `fw-` prefix.

## Arithmetic and comparison expressions

| Operator | Explanation |
|---|---|
| `+` | Adds numbers. |
| `-` | Subtracts the right number from the left number. |
| `*` | Multiplies numbers. |
| `/` | Divides the left number by the right number. |
| `>` | Returns true when the left value is greater. |
| `>=` | Returns true when the left value is greater or equal. |
| `<` | Returns true when the left value is smaller. |
| `<=` | Returns true when the left value is smaller or equal. |
| `==` | Returns true when values are equal. |
| `!=` | Returns true when values are different. |

Arithmetic is evaluated from left to right. The simple expression language does not apply conventional multiplication-before-addition precedence. Split a complex formula into separate mapping fields when precedence matters.

### `round`

```yaml
amount:
  path: $.amount
  round:
    scale: 2
```

Rounds a numeric result to the requested number of decimal places using half-up behavior.

## Type conversion

Use `cast` or `type` to select a target type. `fieldType` and `targetType` are accepted aliases for `type`.

| Type | Explanation |
|---|---|
| `STRING` | Converts the value to text. |
| `INT` | Converts to a signed 32-bit whole number. |
| `INTEGER` | Alias for `INT`. |
| `LONG` | Converts to a signed 64-bit whole number. |
| `DOUBLE` | Converts to a double-precision floating-point number. |
| `DECIMAL` | Converts to a precise decimal value and supports scale and precision controls. |
| `BOOLEAN` | Converts recognized boolean input to `true` or `false`. |
| `TIMESTAMP` | Parses a time and returns epoch milliseconds. |
| `DATE` | Parses and returns an ISO calendar date. |
| `TIME` | Parses and returns an ISO time of day. |
| `JSON` | Parses JSON text into its JSON value. |
| `OBJECT` | Requires or parses an object/map value. |
| `ARRAY` | Requires or parses an array/list value. |

### `date_format`

Defines the input pattern for `TIMESTAMP`, `DATE`, or `TIME`. Without it, the runtime expects standard ISO input.

```yaml
event_date:
  path: $.dateText
  cast: date
  date_format: "MM/dd/yyyy"
```

### `timestamp`

```yaml
event_time:
  path: $.eventTime
  timestamp: parse
```

Parses a string as a timestamp and returns epoch milliseconds. The configured `timestamp` value enables the transform; `date_format` controls a custom input pattern. Prefer `cast: timestamp` in new mappings because its intent is clearer.

### Decimal options

| Option | Explanation |
|---|---|
| `decimalScale` | Sets the number of digits after the decimal point. |
| `decimalPrecision` | Sets the maximum total number of digits. |
| `decimalScalePolicy` | Chooses what happens when the value has more fractional digits than the scale allows. |

### Decimal scale policies

| Policy | Explanation |
|---|---|
| `FAIL` | Reports an error when changing the scale would require rounding. |
| `ROUND` | Rounds to the requested scale using half-up behavior. |
| `TRUNCATE` | Removes extra fractional digits without rounding away from zero. |

### Numeric overflow policies

| Policy | Explanation |
|---|---|
| `ERROR` | Reports an error when the value is outside the target range or precision. |
| `CLAMP` | Returns the closest minimum or maximum representable value. |
| `DEFAULT` | Returns the configured default value. |

## Array selection modes

Given `names = [cpu, mem, disk]`:

| Mode | Explanation | Result |
|---|---|---|
| `FIRST` | Returns the first selected value. | `cpu` |
| `LAST` | Returns the last selected value. | `disk` |
| `INDEX` | Returns the value at `array_index`. Indexes start at zero. | index `1` → `mem` |
| `ONLY` | Returns the value only when exactly one value exists. Other cardinalities produce an error. | one value or error |
| `FILTER_FIRST` | Returns the first value selected by a filtered JSONPath. | first match |
| `FILTER_ALL` | Returns every value selected by a filtered JSONPath. | list of matches |
| `COUNT` | Returns the number of selected values. | `3` |
| `COLLECT` | Returns all selected values as a list. | `[cpu,mem,disk]` |
| `JOIN` | Converts selected values to text and joins them with `delimiter`. | `cpu|mem|disk` |

### `array_index`

Selects the zero-based position used by `array_mode: INDEX`.

### `delimiter`

Selects the text placed between values used by `array_mode: JOIN`. The default delimiter is a comma.

## Array transformation operations

### `filter`

```yaml
high_signals:
  path: $.signals[*]
  filter: "item.value >= 80"
```

Keeps array items matching a simple condition. Supported comparison symbols are `>=`, `<=`, `==`, `!=`, `>`, and `<`.

### `map`

```yaml
readings:
  path: $.signals[*]
  map:
    metric: item.name
    reading: item.value
```

Creates a new object for each item. Values may read an item path such as `item.name` or use a constant.

### `flatten`

```yaml
flat_groups:
  path: $.groups
  flatten: true
```

Flattens one level of nested arrays into a single array.

### `distinct`

```yaml
unique_tags:
  path: $.tags[*]
  distinct: true
```

Removes duplicate values while preserving the first occurrence order.

### Array aggregates

| Aggregate | Explanation |
|---|---|
| `count` | Returns the number of selected values. |
| `sum` | Adds selected numeric values. |
| `min` | Returns the smallest selected value. |
| `max` | Returns the largest selected value. |

## Object operations

### `object`

```yaml
customer:
  object:
    id: $.customerId
    email: $.customerEmail
```

Builds a new object. Each property may read a different input path. Dotted property names create nested properties.

### `merge`

```yaml
profile:
  merge:
    - $.profile.basic
    - $.profile.preferences
```

Combines selected objects into one output object. Later objects supply values for keys that overlap earlier objects.

### Dotted output fields

```yaml
output: OBJECT
fields:
  customer.id: $.customerId
```

Creates nested output when the mapping uses object output. With flat output, the dotted name remains a flat key.

## Missing, null, array, object, type, and overflow policies

### `onMissing`

Controls a path that does not exist.

| Action | Explanation |
|---|---|
| `NULL` | Emits the field with a null value. |
| `SKIP_FIELD` | Omits the output field. |
| `ERROR` | Adds a missing-value field error. |

### `onNull`

Controls an explicitly null input value.

| Action | Explanation |
|---|---|
| `ALLOW` | Keeps null in the output. |
| `DEFAULT` | Uses `default` or `defaultValue`. |
| `ERROR` | Adds a null-value field error. |

### `onArray`

Controls an array when the field expects a scalar.

| Action | Explanation |
|---|---|
| `USE_PICK` | Allows an array selection mode such as `FIRST` or `INDEX` to choose a scalar. |
| `JSON_STRING` | Serializes the array as JSON text. |
| `ERROR` | Adds an array/type field error. |

### `onObject`

Controls an object when the field expects another representation.

| Action | Explanation |
|---|---|
| `NATIVE` | Keeps the object as a native JSON object. |
| `JSON_STRING` | Serializes the object as JSON text. |
| `ERROR` | Adds an object/type field error. |

### `onTypeMismatch`

Controls a value that does not match the requested type.

| Action | Explanation |
|---|---|
| `COERCE` | Attempts a supported conversion. |
| `STRINGIFY` | Returns the original value as text when conversion cannot produce the requested type. |
| `DEFAULT` | Returns `default` or `defaultValue`. |
| `ERROR` | Adds a type-conversion field error. |

### `onOverflow`

Controls a number outside the target range or decimal precision.

| Action | Explanation |
|---|---|
| `ERROR` | Adds a numeric overflow error. |
| `CLAMP` | Returns the nearest allowed minimum or maximum. |
| `DEFAULT` | Returns the configured default. |

### `default` and `defaultValue`

Supply the replacement used by null, mismatch, overflow, lookup-miss, and field-error policies that select a default.

### `strict`

Enables strict handling for the field. Use it when invalid input must not be accepted through permissive conversion behavior.

## Validation operations

### `required`

```yaml
event_id:
  path: $.event.id
  required: true
```

Adds an error when the value is missing.

### String-form `validate`

```yaml
event_id:
  path: $.event.id
  validate: "^evt-"
```

Treats the string as a regular-expression pattern.

### Validation map

| Rule | Explanation |
|---|---|
| `required` | Requires a present value. |
| `pattern` | Requires text to match a regular expression. |
| `min` | Requires a number to be at least the configured minimum. |
| `max` | Requires a number to be no greater than the configured maximum. |
| `one_of` | Requires the value to equal one member of the configured list. |

## Field-level error actions

`on_error` changes the result of one field after a transformation or validation error.

| Action | Explanation |
|---|---|
| `SKIP_FIELD` | Removes the failed field from the output. |
| `SET_NULL` | Emits the field with a null value. |
| `SET_DEFAULT` | Emits `on_error.value`. |

Example:

```yaml
age:
  path: $.age
  cast: int
  on_error:
    action: SET_DEFAULT
    value: 0
```

## Data-protection operations

### `mask`

```yaml
token:
  path: $.token
  mask: last4
```

Replaces all but the last four characters with `*`. Values four characters or shorter become `****`.

### `sensitive`

```yaml
token:
  path: $.token
  sensitive: true
```

Marks a field for protected display and applies the runtime's masking behavior.

### `hash`

```yaml
customer_hash:
  path: $.customerId
  hash: sha256
```

Creates a hexadecimal digest with the configured message-digest algorithm. Hashing is one-way and deterministic for the same input.

### `redact`

```yaml
secret:
  path: $.secret
  redact: true
```

Replaces the field value with null so the secret is not exposed downstream.

### `encrypt`

```yaml
encrypted_secret:
  path: $.secret
  encrypt:
    key_ref: payments
```

Encrypts text with AES-GCM. `key_ref` identifies a key supplied by runtime configuration. Output contains the initialization value and ciphertext. A fresh initialization value makes output nondeterministic.

### `decrypt`

```yaml
secret:
  path: $.ciphertext
  decrypt:
    key_ref: payments
```

Decrypts AES-GCM ciphertext using the same runtime key reference. Invalid ciphertext produces a field error.

### Named protection recipes

| Recipe | Explanation |
|---|---|
| `recipe: mask` | Shorthand that enables masking. |
| `recipe: hash` | Shorthand that enables SHA-256 hashing. |
| `recipe: sensitive` | Shorthand that enables sensitive-field handling. |

## Output shapes

| Shape | Explanation |
|---|---|
| `OBJECT` | Builds nested objects from dotted field names. |
| `FLAT_OBJECT` | Returns one flat object and preserves field names as keys. |
| `JSON_STRING` | Returns serialized JSON text. |
| `PRIMITIVE` | Returns the single mapped value directly when the mapping has one output field. |
| `BYTES` | Returns serialized output bytes for runtimes that need byte-oriented output. |

`outputMode` is an accepted top-level spelling. `output: FLAT_OBJECT` and `output: { shape: FLAT_OBJECT }` are supported forms.

## Host output options

These options are selected by the host runtime when materializing the compiled result.

### Complex-value modes

| Mode | Explanation |
|---|---|
| `NATIVE_JSON` | Keeps arrays and objects as native JSON values. |
| `JSON_STRING` | Serializes arrays and objects into JSON text. |
| `ERROR` | Rejects complex values where the requested output cannot contain them. |

### Field naming policies

| Policy | Explanation |
|---|---|
| `AS_IS` | Keeps mapping field names unchanged. |
| `SNAKE_CASE` | Converts output field names to `snake_case`. |
| `CAMEL_CASE` | Converts output field names to `camelCase`. |

## Mapping-level error policy

```yaml
errorPolicy:
  onTransformationError: ROUTE_TO_DLQ
  onValidationFailure: SKIP_RECORD
  onTypeMismatch: REDACT_AND_PROCEED
  dlqTopicTemplate: "${inputTopic}.flowplane.dlq"
  includeOriginalPayload: false
  includeErrorMetadata: true
```

### Error-policy fields

| Field | Explanation |
|---|---|
| `onTransformationError` | Action requested when a transform cannot complete. |
| `onValidationFailure` | Action requested when validation rejects the record. |
| `onTypeMismatch` | Action requested for a record-level type failure. |
| `dlqTopicTemplate` / `dlqTopic` | Template used by a host that routes records to a dead-letter topic. |
| `includeOriginalPayload` | Controls whether error output may include the original input. |
| `includeErrorMetadata` | Controls whether structured error metadata is included. |

### Mapping-level actions

| Action | Explanation |
|---|---|
| `FAIL_PIPELINE` | Reports failure so the host can stop or fail the current processing path. |
| `SKIP_RECORD` | Requests that the host omit the failed record. |
| `ROUTE_TO_DLQ` | Requests that the host publish the failed record to its dead-letter destination. |
| `REDACT_AND_PROCEED` | Removes sensitive error content and allows processing to continue where supported. |

## Error-output policy

```yaml
errorOutput:
  action: EMIT_TO_TOPIC
  format: CLOUD_EVENTS
  topicTemplate: "errors.${inputTopic}"
  headers:
    - tenantId
    - runtimeId
  maxPayloadBytes: 4096
  includeRuntimeMetadata: true
```

### Error-output fields

| Field | Explanation |
|---|---|
| `action` | Tells the host what delivery behavior is requested. |
| `format` | Selects the error document structure. |
| `topicTemplate` | Names the error topic or destination template. |
| `headers` | Lists context values to copy into error output headers. |
| `maxPayloadBytes` | Limits error payload size. Values less than one use the default of 4096 bytes. |
| `includeRuntimeMetadata` | Controls whether runtime details are included. |
| `template` | Defines fields for `CUSTOM` error output. |

### Error-output actions

| Action | Explanation |
|---|---|
| `ROUTE_TO_DLQ` | Requests delivery to the configured dead-letter destination. |
| `EMIT_TO_TOPIC` | Requests delivery to `topicTemplate`. |
| `FAIL_PIPELINE` | Requests pipeline failure instead of emitting an error record. |
| `DROP` | Requests that the error record be discarded. |
| `RETRY` | Requests host-managed retry behavior. |

### Error-output formats

| Format | Explanation |
|---|---|
| `ENVELOPE` | Wraps original/error context in the standard Flowplane error envelope. |
| `FIELD_ERRORS` | Focuses output on the list of failed fields and their errors. |
| `COMPACT` | Uses a reduced error representation for smaller payloads. |
| `CLOUD_EVENTS` | Wraps the error using CloudEvents-compatible structure. |
| `CUSTOM` | Uses the configured `template` fields. |

The mapping stores these policies. The host integration performs transport actions such as retry, topic publication, acknowledgement, or dead-letter delivery.

## Stateless boundary and rejected operations

Flowplane accepts record-local transformations only. It rejects mapping keys that imply stateful processing:

| Rejected concept | Why it is outside a mapping |
|---|---|
| `join` / `joins` | A join needs data from more than one record or stream. |
| `window` / `windows` | A window needs time-based state across records. |
| `state`, `state_store`, `stateful` | State belongs to the host stream processor. |
| `session` / `sessions` | Sessions require keyed state and timers. |
| `timer` / `timers` | Timers require a stateful runtime scheduler. |
| `watermark` / `watermarks` | Watermarks are host event-time controls. |

Kafka, Flink, Pulsar, Spark, NiFi, or another host owns transport, delivery, retries, acknowledgement, ordering, checkpoints, backpressure, windows, and state.

## Verification

The operation surface was checked on 2026-07-22 with 25 compiler/runtime contract tests and one exact public-fixture comparison. All 26 checks passed.

See the [verification record](../examples/operations/verification.json) for the runtime revision, result, and fixture hashes. All examples use synthetic data.
