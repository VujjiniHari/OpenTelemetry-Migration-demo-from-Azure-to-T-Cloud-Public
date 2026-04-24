# OpenTelemetry Demo — AKS Deployment Architecture

> Open this file in VSCode and press `Ctrl+Shift+V` to see the rendered diagram.

```mermaid
flowchart TB

    %% ── External ──────────────────────────────────────────────────────────────
    subgraph EXT["🌐  External"]
        USER(["👤  Users / Browser"])
        LG["🔄  loadgenerator\nLocust — simulates traffic"]
    end

    %% ── Gateway ───────────────────────────────────────────────────────────────
    subgraph GW["⚡  Gateway Layer"]
        ALB[/"☁️  Azure Load Balancer\n108.141.153.34 : 8080"\]
        FP["🔀  frontendproxy\nEnvoy reverse proxy"]
    end

    %% ── Frontend ──────────────────────────────────────────────────────────────
    subgraph FEL["🖥️  Frontend Layer"]
        FE["🌐  frontend\nNext.js — Astronomy Shop UI"]
        IMG["🖼️  imageprovider\nNginx — serves product images"]
    end

    %% ── Core Business Services ────────────────────────────────────────────────
    subgraph BIZ["🛍️  Business Services"]
        direction LR
        ADS["📢  adservice\nJava"]
        PROD["📦  productcatalogservice\nGo"]
        REC["💡  recommendationservice\nPython"]
        CUR["💱  currencyservice\nC++"]
        CART["🛒  cartservice\n.NET"]
        CHK["✅  checkoutservice\nGo — order orchestrator"]
        PAY["💳  paymentservice\nJavaScript"]
        SHIP["🚚  shippingservice\nRust"]
        QUOTE["🧾  quoteservice\nPHP"]
        EMAIL["📧  emailservice\nRuby"]
    end

    %% ── Async / Messaging ─────────────────────────────────────────────────────
    subgraph MSG["📨  Messaging (Async)"]
        KAFKA[("📨  kafka\nApache Kafka\nports: 9092 / 9093")]
        ACC["🧮  accountingservice\nKotlin — Kafka consumer"]
        FRAUD["🔍  frauddetectionservice\nKotlin — Kafka consumer"]
    end

    %% ── Data Layer ────────────────────────────────────────────────────────────
    subgraph DATA["🗄️  Databases & Storage"]
        VALKEY[("🔴  valkey\nRedis-compatible\nport: 6379\ncart session data")]
        OS[("🔵  opensearch\nOpenSearch 2.15\nStatefulSet\nports: 9200 / 9300\nlog storage")]
    end

    %% ── Observability Stack ───────────────────────────────────────────────────
    subgraph OBS["📊  Observability Stack"]
        OTELCOL["⚙️  otelcol\nOTel Collector contrib\nOTLP gRPC: 4317\nOTLP HTTP: 4318"]
        JAEGER["🔭  jaeger\nDistributed Tracing\nall-in-one 1.53.0\nUI: port 16686"]
        PROM["📈  prometheus\nMetrics backend\nv2.53.1  port: 9090"]
        GRAFANA["📉  grafana\nDashboards\nv11.1.0  port: 80"]
    end

    %% ── Feature Flags ─────────────────────────────────────────────────────────
    FLAGD["🚩  flagd\nOpenFeature\nfeature flag service\nport: 8013"]

    %% ══════════════════════════════════════════════════════════════════════════
    %% Traffic flow
    %% ══════════════════════════════════════════════════════════════════════════
    USER -->|"HTTPS :8080"| ALB
    LG   -->|"simulated load"| ALB
    ALB  --> FP
    FP   -->|"routes"| FE
    FP   -->|"images"| IMG

    %% Frontend → Services
    FE --> ADS
    FE --> PROD
    FE --> REC
    FE --> CUR
    FE --> CART
    FE --> CHK

    %% Checkout orchestrates the order
    CHK -->|"reserve & clear"| CART
    CHK --> PAY
    CHK --> SHIP
    CHK --> QUOTE
    CHK --> CUR
    CHK --> PROD
    CHK -->|"confirmation"| EMAIL

    %% Cart → Database
    CART -->|"read / write"| VALKEY

    %% Checkout → Kafka (async order events)
    CHK -->|"order placed event"| KAFKA
    KAFKA -->|"consumes"| ACC
    KAFKA -->|"consumes"| FRAUD

    %% ══════════════════════════════════════════════════════════════════════════
    %% Telemetry flow (all services emit OTLP to collector)
    %% ══════════════════════════════════════════════════════════════════════════
    FE      -->|"OTLP traces\nmetrics, logs"| OTELCOL
    FP      -->|"OTLP"| OTELCOL
    CART    -->|"OTLP"| OTELCOL
    CHK     -->|"OTLP"| OTELCOL
    PAY     -->|"OTLP"| OTELCOL
    PROD    -->|"OTLP"| OTELCOL
    SHIP    -->|"OTLP"| OTELCOL
    ADS     -->|"OTLP"| OTELCOL
    REC     -->|"OTLP"| OTELCOL
    CUR     -->|"OTLP"| OTELCOL
    ACC     -->|"OTLP"| OTELCOL
    FRAUD   -->|"OTLP"| OTELCOL
    EMAIL   -->|"OTLP"| OTELCOL
    KAFKA   -->|"OTLP"| OTELCOL

    %% Collector fans out
    OTELCOL -->|"traces"| JAEGER
    OTELCOL -->|"metrics"| PROM
    OTELCOL -->|"logs"| OS

    %% Grafana pulls from backends
    PROM   -->|"PromQL queries"| GRAFANA
    JAEGER -->|"trace queries"| GRAFANA

    %% Feature flags (dashed — optional influence)
    FLAGD -.->|"flags"| FE
    FLAGD -.->|"flags"| LG
    FLAGD -.->|"flags"| CHK
    FLAGD -.->|"flags"| CART
    FLAGD -.->|"flags"| REC

    %% ══════════════════════════════════════════════════════════════════════════
    %% Styling
    %% ══════════════════════════════════════════════════════════════════════════
    classDef gateway    fill:#0078d4,color:#fff,stroke:#005a9e
    classDef frontend   fill:#50b0f0,color:#000,stroke:#0078d4
    classDef service    fill:#e8f4fd,color:#000,stroke:#0078d4
    classDef messaging  fill:#fff3cd,color:#000,stroke:#f0ad4e
    classDef database   fill:#d4edda,color:#000,stroke:#28a745
    classDef observ     fill:#f3e5f5,color:#000,stroke:#7b1fa2
    classDef flagd      fill:#fff0f0,color:#000,stroke:#dc3545
    classDef external   fill:#f8f9fa,color:#000,stroke:#6c757d

    class ALB,FP gateway
    class FE,IMG frontend
    class ADS,PROD,REC,CUR,CART,CHK,PAY,SHIP,QUOTE,EMAIL service
    class KAFKA,ACC,FRAUD messaging
    class VALKEY,OS database
    class OTELCOL,JAEGER,PROM,GRAFANA observ
    class FLAGD flagd
    class USER,LG external
```

---

## Component Count Summary

| Layer | Components | Count |
|---|---|---|
| Gateway | Azure Load Balancer, Envoy (frontendproxy) | 2 |
| Frontend | Next.js frontend, Nginx imageprovider | 2 |
| Business Services | adservice, productcatalog, recommendation, currency, cart, checkout, payment, shipping, quote, email | 10 |
| Async / Messaging | Kafka broker, accountingservice, frauddetectionservice | 3 |
| Databases | Valkey (Redis), OpenSearch | 2 |
| Observability | OTel Collector, Jaeger, Prometheus, Grafana | 4 |
| Feature Flags | flagd | 1 |
| Load Generator | Locust | 1 |
| **Total** | | **25** |

## Key Data Flows

| Flow | Path |
|---|---|
| **User request** | Browser → Load Balancer → Envoy → Next.js → microservices |
| **Order placement** | checkout → Kafka topic → accounting + fraud (async) |
| **Cart persistence** | cartservice ↔ Valkey (Redis) |
| **Telemetry** | All services → OTel Collector → Jaeger (traces) + Prometheus (metrics) + OpenSearch (logs) |
| **Dashboards** | Grafana pulls from Prometheus (metrics) and Jaeger (traces) |
| **Feature flags** | flagd controls failure scenarios in frontend, checkout, cart, recommender |
