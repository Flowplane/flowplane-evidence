version: 1
name: grpc-hard-complexity-v1
error_policy:
  on_transformation_error: ROUTE_TO_DLQ
  on_validation_failure: ROUTE_TO_DLQ
  on_type_mismatch: ROUTE_TO_DLQ
output:
  shape: FLAT_OBJECT
  complexTypes: NATIVE_JSON
  fieldNaming: AS_IS
lookups:
  statusCode:
    submitted: ACCEPTED
    cancelled: CANCELLED
  riskBand:
    LOW: LOW
    MEDIUM: MEDIUM
    HIGH: HIGH
fields:
  demoRunId:
    path: $.run.campaignId
    required: true
  sequence:
    path: $.run.sequence
    cast: long
  eventId:
    path: $.event.id
    required: true
    validate:
      pattern: "^evt-benchmark-"
  orderId:
    path: $.order.id
    required: true
  customerTier:
    path: $.customer.tier
    case_convert: upper
  normalizedStatus:
    path: $.order.status
    lookup:
      dictionary: statusCode
  orderAmountDouble:
    path: $.order.amount
    cast: double
  amountRounded:
    path: $.order.amount
    cast: decimal
    decimalScale: 2
    decimalScalePolicy: ROUND
  eventTypeUpper:
    path: $.event.type
    case_convert: upper
  eventTypeLower:
    path: $.event.type
    case_convert: lower
  receivedAt:
    path: $.event.ts
    cast: timestamp
  region:
    path: $.tenant.missingRegion
    fallback:
      - $.tenant.region
  runtimeConstant:
    constant: flowplane-http-grpc-benchmark
  customerLabel:
    path: $.customer.id
    template: "customer-${value}"
  labelParts:
    path: $.packet.labels
    split:
      by: "|"
  normalizedMessage:
    path: $.packet.message
    normalize_string: true
  loadPlusTen:
    arithmetic: "$.metrics.load + 10"
  hugeIntClamped:
    path: $.metrics.huge
    cast: int
    onOverflow: CLAMP
  badIntDefault:
    path: $.metrics.badInt
    cast: int
    onTypeMismatch: DEFAULT
    default: -1
  customerEmailMasked:
    path: $.customer.email
    mask: last4
  customerSsnHashed:
    path: $.customer.ssn
    hash: sha256
  traceHash:
    path: $.event.trace
    hash: sha256
  mappingSchemaVersion:
    path: $.benchmark.mappingSchemaVersion
  signalNames:
    path: $.signals[*].name
    array_mode: JOIN
    delimiter: '|'
  signalCount:
    path: $.signals[*]
    array_mode: COUNT
  firstHotSignal:
    path: $.signals[?(@.value >= 70)].name
    array_mode: FIRST
  filterFirstSignal:
    path: $.signals[*].name
    array_mode: FILTER_FIRST
  temperature:
    path: $.metrics.tempC
    round:
      scale: 1
  online:
    path: $.metrics.online
    cast: boolean
  currencyLabel:
    path: $.order.currency
    template: "currency-${value}"
  riskBand:
    path: $.customer.risk
    lookup:
      dictionary: riskBand
  defaultedValue:
    path: $.packet.missingValue
    default: fixture-default
  metadataTenant:
    metadata: tenant
  headerSource:
    header: source
  loadAsInt:
    path: $.metrics.load
    cast: int
  loadAsLong:
    path: $.metrics.load
    cast: long
  jsonObject:
    path: $.packet.jsonObjectText
    cast: object
  jsonArray:
    path: $.packet.jsonArrayText
    cast: array
  businessDate:
    path: $.packet.businessDate
    cast: date
    date_format: MM/dd/yyyy
  shipTime:
    path: $.packet.shipTime
    cast: time
    date_format: HH:mm:ss
  regexMatched:
    path: $.order.id
    regex_match: "^ORD-[0-9]+$"
  regexExtracted:
    path: $.customer.email
    regex_extract: "buyer([0-9]+)@.*"
    sensitive: true
  regexReplaced:
    path: $.customer.ssn
    regex_replace: "[^0-9]"
    replacement: ""
    sensitive: true
  sensitiveEmail:
    path: $.customer.email
    sensitive: true
  redactedSsn:
    path: $.customer.ssn
    redact: true
    sensitive: true
  lastSignal:
    path: $.signals[*].name
    array_mode: LAST
  onlySignal:
    path: $.singleSignals[*].name
    array_mode: ONLY
  indexedSignal:
    path: $.signals[*].name
    array_mode: INDEX
    array_index: 1
  collectedSignals:
    path: $.signals[*].name
    array_mode: COLLECT
  filteredSignals:
    path: $.signals[?(@.value >= 70)].name
    array_mode: FILTER_ALL
  flattenedSignals:
    path: $.signals[*].name
    flatten: true
  distinctSignalCategories:
    path: $.signals[*].category
    distinct: true
  signalValueSum:
    path: $.signals[*].value
    aggregate: sum
  signalValueMin:
    path: $.signals[*].value
    aggregate: min
  signalValueMax:
    path: $.signals[*].value
    aggregate: max
  signalValueCount:
    path: $.signals[*].value
    aggregate: count
  mappedHotSignals:
    path: $.signals[*]
    filter: "item.value > 70"
    map:
      name: item.name
      category: item.category
  arithmeticExpression:
    expression: "$.metrics.tempC * 1.8 + 32"
    round:
      scale: 2
  booleanExpression:
    expression: "$.metrics.load >= 50"
  policyPrefix:
    path: $.packet.policyNumber
    substring:
      start: 0
      end: 7
  objectProjection:
    object:
      order.id: $.order.id
      event.id: $.event.id
  mergedContext:
    merge:
      - $.order
      - $.customer
  coalescedValue:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.packet.missing
          - $.customer.id
          - type: CONST
            value: fallback
  caseValue:
    valueExpr:
      case:
        branches:
          - when:
              path: $.metrics.load
              operator: GTE
              value: 50
            then: loaded
        else: idle
  lookupExpression:
    valueExpr:
      lookup:
        dictionary: riskBand
        path: $.customer.risk
  functionConcat:
    valueExpr:
      function:
        name: concat
        args:
          - $.order.id
          - type: CONST
            value: '-'
          - $.customer.id
  functionUpper:
    valueExpr:
      function:
        name: upper
        args:
          - $.order.status
  functionLower:
    valueExpr:
      function:
        name: lower
        args:
          - $.order.status
  functionTrim:
    valueExpr:
      function:
        name: trim
        args:
          - $.packet.message
  functionSubstring:
    valueExpr:
      function:
        name: substring
        args:
          - $.packet.policyNumber
          - type: CONST
            value: 4
          - type: CONST
            value: 7
  functionSplit:
    valueExpr:
      function:
        name: split
        args:
          - $.packet.policyNumber
          - type: CONST
            value: '-'
  functionRound:
    valueExpr:
      function:
        name: round
        args:
          - $.order.amount
          - type: CONST
            value: 1
  functionHash:
    valueExpr:
      function:
        name: hash
        args:
          - $.customer.email
  missingAsNull:
    path: $.packet.notPresent
    onMissing: NULL
  itemsAsJson:
    path: $.signals
    onArray: JSON_STRING
  customerAsJson:
    path: $.customer
    onObject: JSON_STRING
  decimalTruncated:
    path: $.order.amount
    cast: decimal
    decimalScale: 1
    decimalScalePolicy: TRUNCATE
  wideField0001:
    path: $.wide.field0001
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0002:
    path: $.wide.field0002
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0003:
    path: $.wide.field0003
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0004:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0004
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0005:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0005
          - $.wide.field0005
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0006:
    path: $.wide.field0006
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0007:
    path: $.wide.field0007
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0008:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0008
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0009:
    path: $.wide.field0009
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0010:
    path: $.wide.field0010
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0011:
    path: $.wide.field0011
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0012:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0012
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0013:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0013
          - $.wide.field0013
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0014:
    path: $.wide.field0014
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0015:
    path: $.wide.field0015
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0016:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0016
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0017:
    path: $.wide.field0017
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0018:
    path: $.wide.field0018
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0019:
    path: $.wide.field0019
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0020:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0020
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0021:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0021
          - $.wide.field0021
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0022:
    path: $.wide.field0022
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0023:
    path: $.wide.field0023
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0024:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0024
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0025:
    path: $.wide.field0025
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0026:
    path: $.wide.field0026
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0027:
    path: $.wide.field0027
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0028:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0028
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0029:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0029
          - $.wide.field0029
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0030:
    path: $.wide.field0030
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0031:
    path: $.wide.field0031
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0032:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0032
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0033:
    path: $.wide.field0033
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0034:
    path: $.wide.field0034
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0035:
    path: $.wide.field0035
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0036:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0036
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0037:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0037
          - $.wide.field0037
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0038:
    path: $.wide.field0038
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0039:
    path: $.wide.field0039
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0040:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0040
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0041:
    path: $.wide.field0041
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0042:
    path: $.wide.field0042
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0043:
    path: $.wide.field0043
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0044:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0044
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0045:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0045
          - $.wide.field0045
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0046:
    path: $.wide.field0046
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0047:
    path: $.wide.field0047
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0048:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0048
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0049:
    path: $.wide.field0049
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0050:
    path: $.wide.field0050
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0051:
    path: $.wide.field0051
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0052:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0052
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0053:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0053
          - $.wide.field0053
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0054:
    path: $.wide.field0054
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0055:
    path: $.wide.field0055
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0056:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0056
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0057:
    path: $.wide.field0057
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0058:
    path: $.wide.field0058
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0059:
    path: $.wide.field0059
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0060:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0060
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0061:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0061
          - $.wide.field0061
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0062:
    path: $.wide.field0062
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0063:
    path: $.wide.field0063
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0064:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0064
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0065:
    path: $.wide.field0065
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0066:
    path: $.wide.field0066
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0067:
    path: $.wide.field0067
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0068:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0068
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0069:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0069
          - $.wide.field0069
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0070:
    path: $.wide.field0070
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0071:
    path: $.wide.field0071
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0072:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0072
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0073:
    path: $.wide.field0073
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0074:
    path: $.wide.field0074
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0075:
    path: $.wide.field0075
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0076:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0076
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0077:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0077
          - $.wide.field0077
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0078:
    path: $.wide.field0078
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0079:
    path: $.wide.field0079
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0080:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0080
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0081:
    path: $.wide.field0081
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0082:
    path: $.wide.field0082
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0083:
    path: $.wide.field0083
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0084:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0084
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0085:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0085
          - $.wide.field0085
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0086:
    path: $.wide.field0086
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0087:
    path: $.wide.field0087
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0088:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0088
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0089:
    path: $.wide.field0089
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0090:
    path: $.wide.field0090
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0091:
    path: $.wide.field0091
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0092:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0092
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0093:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0093
          - $.wide.field0093
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0094:
    path: $.wide.field0094
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0095:
    path: $.wide.field0095
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0096:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0096
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0097:
    path: $.wide.field0097
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0098:
    path: $.wide.field0098
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0099:
    path: $.wide.field0099
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0100:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0100
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0101:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0101
          - $.wide.field0101
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0102:
    path: $.wide.field0102
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0103:
    path: $.wide.field0103
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0104:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0104
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0105:
    path: $.wide.field0105
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0106:
    path: $.wide.field0106
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0107:
    path: $.wide.field0107
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0108:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0108
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0109:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0109
          - $.wide.field0109
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0110:
    path: $.wide.field0110
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0111:
    path: $.wide.field0111
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0112:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0112
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0113:
    path: $.wide.field0113
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0114:
    path: $.wide.field0114
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0115:
    path: $.wide.field0115
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0116:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0116
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0117:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0117
          - $.wide.field0117
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0118:
    path: $.wide.field0118
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0119:
    path: $.wide.field0119
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0120:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0120
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0121:
    path: $.wide.field0121
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0122:
    path: $.wide.field0122
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0123:
    path: $.wide.field0123
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0124:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0124
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0125:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0125
          - $.wide.field0125
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0126:
    path: $.wide.field0126
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0127:
    path: $.wide.field0127
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0128:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0128
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0129:
    path: $.wide.field0129
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0130:
    path: $.wide.field0130
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0131:
    path: $.wide.field0131
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0132:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0132
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0133:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0133
          - $.wide.field0133
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0134:
    path: $.wide.field0134
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0135:
    path: $.wide.field0135
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0136:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0136
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0137:
    path: $.wide.field0137
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0138:
    path: $.wide.field0138
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0139:
    path: $.wide.field0139
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0140:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0140
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0141:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0141
          - $.wide.field0141
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0142:
    path: $.wide.field0142
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0143:
    path: $.wide.field0143
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0144:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0144
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0145:
    path: $.wide.field0145
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0146:
    path: $.wide.field0146
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0147:
    path: $.wide.field0147
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0148:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0148
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0149:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0149
          - $.wide.field0149
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0150:
    path: $.wide.field0150
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0151:
    path: $.wide.field0151
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0152:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0152
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0153:
    path: $.wide.field0153
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0154:
    path: $.wide.field0154
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0155:
    path: $.wide.field0155
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0156:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0156
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0157:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0157
          - $.wide.field0157
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0158:
    path: $.wide.field0158
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0159:
    path: $.wide.field0159
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0160:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0160
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0161:
    path: $.wide.field0161
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0162:
    path: $.wide.field0162
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0163:
    path: $.wide.field0163
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0164:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0164
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0165:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0165
          - $.wide.field0165
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0166:
    path: $.wide.field0166
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0167:
    path: $.wide.field0167
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0168:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0168
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0169:
    path: $.wide.field0169
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0170:
    path: $.wide.field0170
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0171:
    path: $.wide.field0171
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0172:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0172
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0173:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0173
          - $.wide.field0173
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0174:
    path: $.wide.field0174
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0175:
    path: $.wide.field0175
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0176:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0176
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0177:
    path: $.wide.field0177
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0178:
    path: $.wide.field0178
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0179:
    path: $.wide.field0179
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0180:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0180
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0181:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0181
          - $.wide.field0181
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0182:
    path: $.wide.field0182
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0183:
    path: $.wide.field0183
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0184:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0184
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0185:
    path: $.wide.field0185
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0186:
    path: $.wide.field0186
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0187:
    path: $.wide.field0187
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0188:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0188
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0189:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0189
          - $.wide.field0189
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0190:
    path: $.wide.field0190
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0191:
    path: $.wide.field0191
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0192:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0192
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0193:
    path: $.wide.field0193
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0194:
    path: $.wide.field0194
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0195:
    path: $.wide.field0195
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0196:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0196
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0197:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0197
          - $.wide.field0197
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0198:
    path: $.wide.field0198
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0199:
    path: $.wide.field0199
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0200:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0200
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0201:
    path: $.wide.field0201
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0202:
    path: $.wide.field0202
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0203:
    path: $.wide.field0203
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0204:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0204
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0205:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0205
          - $.wide.field0205
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0206:
    path: $.wide.field0206
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0207:
    path: $.wide.field0207
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0208:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0208
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0209:
    path: $.wide.field0209
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0210:
    path: $.wide.field0210
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0211:
    path: $.wide.field0211
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0212:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0212
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0213:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0213
          - $.wide.field0213
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0214:
    path: $.wide.field0214
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0215:
    path: $.wide.field0215
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0216:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0216
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0217:
    path: $.wide.field0217
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0218:
    path: $.wide.field0218
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0219:
    path: $.wide.field0219
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0220:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0220
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0221:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0221
          - $.wide.field0221
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0222:
    path: $.wide.field0222
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0223:
    path: $.wide.field0223
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0224:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0224
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0225:
    path: $.wide.field0225
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0226:
    path: $.wide.field0226
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0227:
    path: $.wide.field0227
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0228:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0228
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0229:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0229
          - $.wide.field0229
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0230:
    path: $.wide.field0230
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0231:
    path: $.wide.field0231
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0232:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0232
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0233:
    path: $.wide.field0233
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0234:
    path: $.wide.field0234
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0235:
    path: $.wide.field0235
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0236:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0236
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0237:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0237
          - $.wide.field0237
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0238:
    path: $.wide.field0238
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0239:
    path: $.wide.field0239
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0240:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0240
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0241:
    path: $.wide.field0241
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0242:
    path: $.wide.field0242
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0243:
    path: $.wide.field0243
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0244:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0244
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0245:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0245
          - $.wide.field0245
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0246:
    path: $.wide.field0246
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0247:
    path: $.wide.field0247
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0248:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0248
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0249:
    path: $.wide.field0249
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0250:
    path: $.wide.field0250
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0251:
    path: $.wide.field0251
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0252:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0252
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0253:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0253
          - $.wide.field0253
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0254:
    path: $.wide.field0254
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0255:
    path: $.wide.field0255
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0256:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0256
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0257:
    path: $.wide.field0257
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0258:
    path: $.wide.field0258
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0259:
    path: $.wide.field0259
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0260:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0260
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0261:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0261
          - $.wide.field0261
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0262:
    path: $.wide.field0262
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0263:
    path: $.wide.field0263
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0264:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0264
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0265:
    path: $.wide.field0265
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0266:
    path: $.wide.field0266
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0267:
    path: $.wide.field0267
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0268:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0268
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0269:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0269
          - $.wide.field0269
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0270:
    path: $.wide.field0270
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0271:
    path: $.wide.field0271
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0272:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0272
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0273:
    path: $.wide.field0273
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0274:
    path: $.wide.field0274
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0275:
    path: $.wide.field0275
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0276:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0276
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0277:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0277
          - $.wide.field0277
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0278:
    path: $.wide.field0278
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0279:
    path: $.wide.field0279
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0280:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0280
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0281:
    path: $.wide.field0281
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0282:
    path: $.wide.field0282
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0283:
    path: $.wide.field0283
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0284:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0284
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0285:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0285
          - $.wide.field0285
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0286:
    path: $.wide.field0286
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0287:
    path: $.wide.field0287
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0288:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0288
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0289:
    path: $.wide.field0289
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0290:
    path: $.wide.field0290
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0291:
    path: $.wide.field0291
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0292:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0292
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0293:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0293
          - $.wide.field0293
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0294:
    path: $.wide.field0294
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0295:
    path: $.wide.field0295
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0296:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0296
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0297:
    path: $.wide.field0297
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0298:
    path: $.wide.field0298
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0299:
    path: $.wide.field0299
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0300:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0300
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0301:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0301
          - $.wide.field0301
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0302:
    path: $.wide.field0302
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0303:
    path: $.wide.field0303
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0304:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0304
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0305:
    path: $.wide.field0305
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0306:
    path: $.wide.field0306
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0307:
    path: $.wide.field0307
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0308:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0308
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0309:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0309
          - $.wide.field0309
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0310:
    path: $.wide.field0310
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0311:
    path: $.wide.field0311
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0312:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0312
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0313:
    path: $.wide.field0313
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0314:
    path: $.wide.field0314
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0315:
    path: $.wide.field0315
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0316:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0316
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0317:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0317
          - $.wide.field0317
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0318:
    path: $.wide.field0318
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0319:
    path: $.wide.field0319
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0320:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0320
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0321:
    path: $.wide.field0321
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0322:
    path: $.wide.field0322
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0323:
    path: $.wide.field0323
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0324:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0324
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0325:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0325
          - $.wide.field0325
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0326:
    path: $.wide.field0326
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0327:
    path: $.wide.field0327
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0328:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0328
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0329:
    path: $.wide.field0329
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0330:
    path: $.wide.field0330
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0331:
    path: $.wide.field0331
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0332:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0332
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0333:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0333
          - $.wide.field0333
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0334:
    path: $.wide.field0334
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0335:
    path: $.wide.field0335
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0336:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0336
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0337:
    path: $.wide.field0337
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0338:
    path: $.wide.field0338
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0339:
    path: $.wide.field0339
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0340:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0340
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0341:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0341
          - $.wide.field0341
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0342:
    path: $.wide.field0342
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0343:
    path: $.wide.field0343
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0344:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0344
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0345:
    path: $.wide.field0345
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0346:
    path: $.wide.field0346
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0347:
    path: $.wide.field0347
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0348:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0348
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0349:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0349
          - $.wide.field0349
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0350:
    path: $.wide.field0350
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0351:
    path: $.wide.field0351
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0352:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0352
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0353:
    path: $.wide.field0353
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0354:
    path: $.wide.field0354
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0355:
    path: $.wide.field0355
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0356:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0356
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0357:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0357
          - $.wide.field0357
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0358:
    path: $.wide.field0358
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0359:
    path: $.wide.field0359
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0360:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0360
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0361:
    path: $.wide.field0361
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0362:
    path: $.wide.field0362
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0363:
    path: $.wide.field0363
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0364:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0364
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0365:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0365
          - $.wide.field0365
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0366:
    path: $.wide.field0366
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0367:
    path: $.wide.field0367
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0368:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0368
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0369:
    path: $.wide.field0369
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0370:
    path: $.wide.field0370
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0371:
    path: $.wide.field0371
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0372:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0372
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0373:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0373
          - $.wide.field0373
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0374:
    path: $.wide.field0374
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0375:
    path: $.wide.field0375
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0376:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0376
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0377:
    path: $.wide.field0377
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0378:
    path: $.wide.field0378
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0379:
    path: $.wide.field0379
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0380:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0380
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0381:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0381
          - $.wide.field0381
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0382:
    path: $.wide.field0382
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0383:
    path: $.wide.field0383
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0384:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0384
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0385:
    path: $.wide.field0385
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0386:
    path: $.wide.field0386
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0387:
    path: $.wide.field0387
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0388:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0388
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0389:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0389
          - $.wide.field0389
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0390:
    path: $.wide.field0390
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0391:
    path: $.wide.field0391
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0392:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0392
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0393:
    path: $.wide.field0393
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0394:
    path: $.wide.field0394
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0395:
    path: $.wide.field0395
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0396:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0396
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0397:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0397
          - $.wide.field0397
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0398:
    path: $.wide.field0398
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0399:
    path: $.wide.field0399
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0400:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0400
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0401:
    path: $.wide.field0401
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0402:
    path: $.wide.field0402
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0403:
    path: $.wide.field0403
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0404:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0404
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0405:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0405
          - $.wide.field0405
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0406:
    path: $.wide.field0406
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0407:
    path: $.wide.field0407
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0408:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0408
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0409:
    path: $.wide.field0409
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0410:
    path: $.wide.field0410
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0411:
    path: $.wide.field0411
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0412:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0412
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0413:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0413
          - $.wide.field0413
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0414:
    path: $.wide.field0414
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0415:
    path: $.wide.field0415
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0416:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0416
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0417:
    path: $.wide.field0417
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0418:
    path: $.wide.field0418
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0419:
    path: $.wide.field0419
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0420:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0420
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0421:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0421
          - $.wide.field0421
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0422:
    path: $.wide.field0422
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0423:
    path: $.wide.field0423
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0424:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0424
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0425:
    path: $.wide.field0425
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0426:
    path: $.wide.field0426
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0427:
    path: $.wide.field0427
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0428:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0428
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0429:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0429
          - $.wide.field0429
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0430:
    path: $.wide.field0430
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0431:
    path: $.wide.field0431
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0432:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0432
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0433:
    path: $.wide.field0433
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0434:
    path: $.wide.field0434
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0435:
    path: $.wide.field0435
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0436:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0436
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0437:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0437
          - $.wide.field0437
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0438:
    path: $.wide.field0438
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0439:
    path: $.wide.field0439
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0440:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0440
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0441:
    path: $.wide.field0441
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0442:
    path: $.wide.field0442
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0443:
    path: $.wide.field0443
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0444:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0444
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0445:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0445
          - $.wide.field0445
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0446:
    path: $.wide.field0446
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0447:
    path: $.wide.field0447
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0448:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0448
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0449:
    path: $.wide.field0449
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0450:
    path: $.wide.field0450
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0451:
    path: $.wide.field0451
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0452:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0452
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0453:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0453
          - $.wide.field0453
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0454:
    path: $.wide.field0454
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0455:
    path: $.wide.field0455
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0456:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0456
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0457:
    path: $.wide.field0457
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0458:
    path: $.wide.field0458
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0459:
    path: $.wide.field0459
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0460:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0460
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0461:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0461
          - $.wide.field0461
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0462:
    path: $.wide.field0462
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0463:
    path: $.wide.field0463
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0464:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0464
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0465:
    path: $.wide.field0465
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0466:
    path: $.wide.field0466
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0467:
    path: $.wide.field0467
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0468:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0468
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0469:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0469
          - $.wide.field0469
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0470:
    path: $.wide.field0470
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0471:
    path: $.wide.field0471
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0472:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0472
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0473:
    path: $.wide.field0473
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0474:
    path: $.wide.field0474
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0475:
    path: $.wide.field0475
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0476:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0476
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0477:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0477
          - $.wide.field0477
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0478:
    path: $.wide.field0478
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0479:
    path: $.wide.field0479
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0480:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0480
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0481:
    path: $.wide.field0481
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0482:
    path: $.wide.field0482
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0483:
    path: $.wide.field0483
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0484:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0484
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0485:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0485
          - $.wide.field0485
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0486:
    path: $.wide.field0486
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0487:
    path: $.wide.field0487
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0488:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0488
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0489:
    path: $.wide.field0489
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0490:
    path: $.wide.field0490
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0491:
    path: $.wide.field0491
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0492:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0492
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0493:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0493
          - $.wide.field0493
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0494:
    path: $.wide.field0494
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0495:
    path: $.wide.field0495
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0496:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0496
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0497:
    path: $.wide.field0497
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0498:
    path: $.wide.field0498
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0499:
    path: $.wide.field0499
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0500:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0500
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0501:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0501
          - $.wide.field0501
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0502:
    path: $.wide.field0502
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0503:
    path: $.wide.field0503
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0504:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0504
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0505:
    path: $.wide.field0505
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0506:
    path: $.wide.field0506
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0507:
    path: $.wide.field0507
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0508:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0508
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0509:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0509
          - $.wide.field0509
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0510:
    path: $.wide.field0510
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0511:
    path: $.wide.field0511
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0512:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0512
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0513:
    path: $.wide.field0513
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0514:
    path: $.wide.field0514
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0515:
    path: $.wide.field0515
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0516:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0516
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0517:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0517
          - $.wide.field0517
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0518:
    path: $.wide.field0518
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0519:
    path: $.wide.field0519
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0520:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0520
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0521:
    path: $.wide.field0521
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0522:
    path: $.wide.field0522
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0523:
    path: $.wide.field0523
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0524:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0524
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0525:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0525
          - $.wide.field0525
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0526:
    path: $.wide.field0526
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0527:
    path: $.wide.field0527
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0528:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0528
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0529:
    path: $.wide.field0529
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0530:
    path: $.wide.field0530
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0531:
    path: $.wide.field0531
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0532:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0532
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0533:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0533
          - $.wide.field0533
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0534:
    path: $.wide.field0534
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0535:
    path: $.wide.field0535
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0536:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0536
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0537:
    path: $.wide.field0537
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0538:
    path: $.wide.field0538
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0539:
    path: $.wide.field0539
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0540:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0540
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0541:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0541
          - $.wide.field0541
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0542:
    path: $.wide.field0542
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0543:
    path: $.wide.field0543
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0544:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0544
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0545:
    path: $.wide.field0545
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0546:
    path: $.wide.field0546
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0547:
    path: $.wide.field0547
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0548:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0548
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0549:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0549
          - $.wide.field0549
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0550:
    path: $.wide.field0550
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0551:
    path: $.wide.field0551
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0552:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0552
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0553:
    path: $.wide.field0553
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0554:
    path: $.wide.field0554
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0555:
    path: $.wide.field0555
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0556:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0556
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0557:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0557
          - $.wide.field0557
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0558:
    path: $.wide.field0558
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0559:
    path: $.wide.field0559
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0560:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0560
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0561:
    path: $.wide.field0561
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0562:
    path: $.wide.field0562
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0563:
    path: $.wide.field0563
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0564:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0564
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0565:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0565
          - $.wide.field0565
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0566:
    path: $.wide.field0566
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0567:
    path: $.wide.field0567
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0568:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0568
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0569:
    path: $.wide.field0569
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0570:
    path: $.wide.field0570
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0571:
    path: $.wide.field0571
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0572:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0572
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0573:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0573
          - $.wide.field0573
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0574:
    path: $.wide.field0574
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0575:
    path: $.wide.field0575
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0576:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0576
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0577:
    path: $.wide.field0577
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0578:
    path: $.wide.field0578
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0579:
    path: $.wide.field0579
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0580:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0580
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0581:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0581
          - $.wide.field0581
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0582:
    path: $.wide.field0582
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0583:
    path: $.wide.field0583
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0584:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0584
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0585:
    path: $.wide.field0585
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0586:
    path: $.wide.field0586
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0587:
    path: $.wide.field0587
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0588:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0588
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0589:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0589
          - $.wide.field0589
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0590:
    path: $.wide.field0590
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0591:
    path: $.wide.field0591
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0592:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0592
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0593:
    path: $.wide.field0593
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0594:
    path: $.wide.field0594
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0595:
    path: $.wide.field0595
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0596:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0596
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0597:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0597
          - $.wide.field0597
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0598:
    path: $.wide.field0598
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0599:
    path: $.wide.field0599
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0600:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0600
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0601:
    path: $.wide.field0601
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0602:
    path: $.wide.field0602
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0603:
    path: $.wide.field0603
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0604:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0604
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0605:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0605
          - $.wide.field0605
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0606:
    path: $.wide.field0606
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0607:
    path: $.wide.field0607
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0608:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0608
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0609:
    path: $.wide.field0609
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0610:
    path: $.wide.field0610
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0611:
    path: $.wide.field0611
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0612:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0612
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0613:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0613
          - $.wide.field0613
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0614:
    path: $.wide.field0614
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0615:
    path: $.wide.field0615
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0616:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0616
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0617:
    path: $.wide.field0617
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0618:
    path: $.wide.field0618
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0619:
    path: $.wide.field0619
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0620:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0620
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0621:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0621
          - $.wide.field0621
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0622:
    path: $.wide.field0622
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0623:
    path: $.wide.field0623
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0624:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0624
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0625:
    path: $.wide.field0625
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0626:
    path: $.wide.field0626
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0627:
    path: $.wide.field0627
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0628:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0628
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0629:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0629
          - $.wide.field0629
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0630:
    path: $.wide.field0630
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0631:
    path: $.wide.field0631
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0632:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0632
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0633:
    path: $.wide.field0633
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0634:
    path: $.wide.field0634
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0635:
    path: $.wide.field0635
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0636:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0636
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0637:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0637
          - $.wide.field0637
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0638:
    path: $.wide.field0638
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0639:
    path: $.wide.field0639
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0640:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0640
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0641:
    path: $.wide.field0641
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0642:
    path: $.wide.field0642
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0643:
    path: $.wide.field0643
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0644:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0644
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0645:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0645
          - $.wide.field0645
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0646:
    path: $.wide.field0646
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0647:
    path: $.wide.field0647
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0648:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0648
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0649:
    path: $.wide.field0649
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0650:
    path: $.wide.field0650
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0651:
    path: $.wide.field0651
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0652:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0652
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0653:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0653
          - $.wide.field0653
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0654:
    path: $.wide.field0654
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0655:
    path: $.wide.field0655
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0656:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0656
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0657:
    path: $.wide.field0657
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0658:
    path: $.wide.field0658
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0659:
    path: $.wide.field0659
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0660:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0660
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0661:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0661
          - $.wide.field0661
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0662:
    path: $.wide.field0662
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0663:
    path: $.wide.field0663
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0664:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0664
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0665:
    path: $.wide.field0665
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0666:
    path: $.wide.field0666
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0667:
    path: $.wide.field0667
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0668:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0668
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0669:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0669
          - $.wide.field0669
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0670:
    path: $.wide.field0670
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0671:
    path: $.wide.field0671
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0672:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0672
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0673:
    path: $.wide.field0673
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0674:
    path: $.wide.field0674
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0675:
    path: $.wide.field0675
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0676:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0676
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0677:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0677
          - $.wide.field0677
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0678:
    path: $.wide.field0678
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0679:
    path: $.wide.field0679
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0680:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0680
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0681:
    path: $.wide.field0681
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0682:
    path: $.wide.field0682
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0683:
    path: $.wide.field0683
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0684:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0684
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0685:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0685
          - $.wide.field0685
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0686:
    path: $.wide.field0686
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0687:
    path: $.wide.field0687
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0688:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0688
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0689:
    path: $.wide.field0689
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0690:
    path: $.wide.field0690
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0691:
    path: $.wide.field0691
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0692:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0692
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0693:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0693
          - $.wide.field0693
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0694:
    path: $.wide.field0694
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0695:
    path: $.wide.field0695
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0696:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0696
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0697:
    path: $.wide.field0697
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0698:
    path: $.wide.field0698
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0699:
    path: $.wide.field0699
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0700:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0700
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0701:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0701
          - $.wide.field0701
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0702:
    path: $.wide.field0702
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0703:
    path: $.wide.field0703
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0704:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0704
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0705:
    path: $.wide.field0705
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0706:
    path: $.wide.field0706
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0707:
    path: $.wide.field0707
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0708:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0708
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0709:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0709
          - $.wide.field0709
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0710:
    path: $.wide.field0710
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0711:
    path: $.wide.field0711
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0712:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0712
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0713:
    path: $.wide.field0713
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0714:
    path: $.wide.field0714
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0715:
    path: $.wide.field0715
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0716:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0716
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0717:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0717
          - $.wide.field0717
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0718:
    path: $.wide.field0718
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0719:
    path: $.wide.field0719
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0720:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0720
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0721:
    path: $.wide.field0721
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0722:
    path: $.wide.field0722
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0723:
    path: $.wide.field0723
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0724:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0724
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0725:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0725
          - $.wide.field0725
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0726:
    path: $.wide.field0726
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0727:
    path: $.wide.field0727
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0728:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0728
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0729:
    path: $.wide.field0729
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0730:
    path: $.wide.field0730
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0731:
    path: $.wide.field0731
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0732:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0732
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0733:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0733
          - $.wide.field0733
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0734:
    path: $.wide.field0734
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0735:
    path: $.wide.field0735
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0736:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0736
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0737:
    path: $.wide.field0737
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0738:
    path: $.wide.field0738
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0739:
    path: $.wide.field0739
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0740:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0740
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0741:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0741
          - $.wide.field0741
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0742:
    path: $.wide.field0742
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0743:
    path: $.wide.field0743
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0744:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0744
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0745:
    path: $.wide.field0745
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0746:
    path: $.wide.field0746
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0747:
    path: $.wide.field0747
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0748:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0748
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0749:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0749
          - $.wide.field0749
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0750:
    path: $.wide.field0750
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0751:
    path: $.wide.field0751
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0752:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0752
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0753:
    path: $.wide.field0753
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0754:
    path: $.wide.field0754
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0755:
    path: $.wide.field0755
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0756:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0756
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0757:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0757
          - $.wide.field0757
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0758:
    path: $.wide.field0758
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0759:
    path: $.wide.field0759
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0760:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0760
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0761:
    path: $.wide.field0761
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0762:
    path: $.wide.field0762
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0763:
    path: $.wide.field0763
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0764:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0764
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0765:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0765
          - $.wide.field0765
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0766:
    path: $.wide.field0766
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0767:
    path: $.wide.field0767
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0768:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0768
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0769:
    path: $.wide.field0769
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0770:
    path: $.wide.field0770
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0771:
    path: $.wide.field0771
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0772:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0772
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0773:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0773
          - $.wide.field0773
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0774:
    path: $.wide.field0774
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0775:
    path: $.wide.field0775
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0776:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0776
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0777:
    path: $.wide.field0777
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0778:
    path: $.wide.field0778
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0779:
    path: $.wide.field0779
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0780:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0780
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0781:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0781
          - $.wide.field0781
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0782:
    path: $.wide.field0782
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0783:
    path: $.wide.field0783
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0784:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0784
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0785:
    path: $.wide.field0785
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0786:
    path: $.wide.field0786
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0787:
    path: $.wide.field0787
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0788:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0788
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0789:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0789
          - $.wide.field0789
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0790:
    path: $.wide.field0790
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0791:
    path: $.wide.field0791
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0792:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0792
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0793:
    path: $.wide.field0793
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0794:
    path: $.wide.field0794
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0795:
    path: $.wide.field0795
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0796:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0796
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0797:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0797
          - $.wide.field0797
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0798:
    path: $.wide.field0798
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0799:
    path: $.wide.field0799
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0800:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0800
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0801:
    path: $.wide.field0801
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0802:
    path: $.wide.field0802
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0803:
    path: $.wide.field0803
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0804:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0804
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0805:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0805
          - $.wide.field0805
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0806:
    path: $.wide.field0806
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0807:
    path: $.wide.field0807
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0808:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0808
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0809:
    path: $.wide.field0809
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0810:
    path: $.wide.field0810
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0811:
    path: $.wide.field0811
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0812:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0812
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0813:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0813
          - $.wide.field0813
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0814:
    path: $.wide.field0814
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0815:
    path: $.wide.field0815
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0816:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0816
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0817:
    path: $.wide.field0817
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0818:
    path: $.wide.field0818
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0819:
    path: $.wide.field0819
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0820:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0820
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0821:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0821
          - $.wide.field0821
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0822:
    path: $.wide.field0822
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0823:
    path: $.wide.field0823
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0824:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0824
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0825:
    path: $.wide.field0825
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0826:
    path: $.wide.field0826
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0827:
    path: $.wide.field0827
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0828:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0828
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0829:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0829
          - $.wide.field0829
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0830:
    path: $.wide.field0830
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0831:
    path: $.wide.field0831
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0832:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0832
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0833:
    path: $.wide.field0833
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0834:
    path: $.wide.field0834
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0835:
    path: $.wide.field0835
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0836:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0836
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0837:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0837
          - $.wide.field0837
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0838:
    path: $.wide.field0838
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0839:
    path: $.wide.field0839
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0840:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0840
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0841:
    path: $.wide.field0841
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0842:
    path: $.wide.field0842
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0843:
    path: $.wide.field0843
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0844:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0844
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0845:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0845
          - $.wide.field0845
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0846:
    path: $.wide.field0846
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0847:
    path: $.wide.field0847
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0848:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0848
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0849:
    path: $.wide.field0849
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0850:
    path: $.wide.field0850
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0851:
    path: $.wide.field0851
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0852:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0852
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0853:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0853
          - $.wide.field0853
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0854:
    path: $.wide.field0854
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0855:
    path: $.wide.field0855
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0856:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0856
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0857:
    path: $.wide.field0857
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0858:
    path: $.wide.field0858
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0859:
    path: $.wide.field0859
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0860:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0860
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0861:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0861
          - $.wide.field0861
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0862:
    path: $.wide.field0862
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0863:
    path: $.wide.field0863
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0864:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0864
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0865:
    path: $.wide.field0865
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0866:
    path: $.wide.field0866
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0867:
    path: $.wide.field0867
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0868:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0868
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0869:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0869
          - $.wide.field0869
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0870:
    path: $.wide.field0870
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0871:
    path: $.wide.field0871
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0872:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0872
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0873:
    path: $.wide.field0873
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0874:
    path: $.wide.field0874
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0875:
    path: $.wide.field0875
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0876:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0876
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0877:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0877
          - $.wide.field0877
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0878:
    path: $.wide.field0878
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0879:
    path: $.wide.field0879
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0880:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0880
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0881:
    path: $.wide.field0881
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0882:
    path: $.wide.field0882
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0883:
    path: $.wide.field0883
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0884:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0884
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0885:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0885
          - $.wide.field0885
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0886:
    path: $.wide.field0886
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0887:
    path: $.wide.field0887
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0888:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0888
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0889:
    path: $.wide.field0889
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0890:
    path: $.wide.field0890
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0891:
    path: $.wide.field0891
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0892:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0892
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0893:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0893
          - $.wide.field0893
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0894:
    path: $.wide.field0894
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0895:
    path: $.wide.field0895
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0896:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0896
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0897:
    path: $.wide.field0897
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0898:
    path: $.wide.field0898
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0899:
    path: $.wide.field0899
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0900:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0900
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0901:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0901
          - $.wide.field0901
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0902:
    path: $.wide.field0902
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0903:
    path: $.wide.field0903
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0904:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0904
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0905:
    path: $.wide.field0905
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0906:
    path: $.wide.field0906
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0907:
    path: $.wide.field0907
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0908:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0908
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0909:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0909
          - $.wide.field0909
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0910:
    path: $.wide.field0910
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0911:
    path: $.wide.field0911
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0912:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0912
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0913:
    path: $.wide.field0913
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0914:
    path: $.wide.field0914
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0915:
    path: $.wide.field0915
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
  wideField0916:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0916
          - type: CONST
            value: ':'
          - $.tenant.region
    normalize_string: true
    case_convert: upper
    template: "joined-${value}"
  wideField0917:
    valueExpr:
      coalesce:
        mode: FIRST_NON_EMPTY
        candidates:
          - $.wide.missing0917
          - $.wide.field0917
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
  wideField0918:
    path: $.wide.field0918
    required: true
    normalize_string: true
    case_convert: upper
    regex_match: "^VALUE-[0-9]{3}-[0-9]{4}$"
    template: "validated-${value}"
  wideField0919:
    path: $.wide.field0919
    required: true
    normalize_string: true
    substring:
      start: 0
      end: 14
    hash: sha256
    template: "digest-${value}"
  wideField0920:
    valueExpr:
      function:
        name: concat
        args:
          - $.wide.field0920
          - type: CONST
            value: ':'
          - $.customer.tier
          - type: CONST
            value: ':'
          - $.order.currency
    normalize_string: true
    case_convert: lower
    regex_replace: "-"
    replacement: "_"
    template: "context-${value}"
  wideField0921:
    path: $.wide.field0921
    required: true
    normalize_string: true
    case_convert: upper
    regex_replace: "VALUE"
    replacement: "WIDE"
    template: "normalized-${value}"
  wideField0922:
    path: $.wide.field0922
    required: true
    normalize_string: true
    case_convert: lower
    regex_extract: "value-([0-9]{3}-[0-9]{4})"
    template: "extracted-${value}"
  wideField0923:
    path: $.wide.field0923
    required: true
    normalize_string: true
    regex_replace: "-"
    replacement: ":"
    substring:
      start: 0
      end: 14
    template: "slice-${value}"
