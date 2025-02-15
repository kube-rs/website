# Observability

This document showcases common techniques for instrumentation:

- **logs** (via [tracing] + [tracing-subscriber] + [EnvFilter])
- **traces** (via [tracing] + [tracing-subscriber] + [opentelemetry-otlp] + [opentelemetry] + [opentelemetry_sdk])
- **metrics** (via [tikv/prometheus](https://github.com/tikv/rust-prometheus) exposed via [actix-web])

and follows the approach of [controller-rs].

Most of this logic happens in `main`, before any machinery starts, so it will liberally `.unwrap()`.

## Adding Logs

We will use the [tracing] library for logging because it allows us reusing the same system for tracing later.

```sh
cargo add tracing
cargo add tracing-subscriber --features=json,env-filter
```

We will configure this in `main` by creating a `json` log layer with an [EnvFilter] picking up on the common `RUST_LOG` environment variable:

```rust
let logger = tracing_subscriber::fmt::layer().json();
let env_filter = EnvFilter::try_from_default_env()
    .or_else(|_| EnvFilter::try_new("info"))
    .unwrap();
```

This can be set as the global collector using:

```rust
Registry::default().with(logger).with(env_filter).init();
```

We will change how the `collector` is built if using **tracing**, but for now, this is sufficient for adding logging.

## Adding Traces

Following on from logging section, we add extra dependencies to let us push traces to an **opentelemetry** collector (sending over gRPC with [tonic]):

```sh
cargo add opentelemetry --features=trace
cargo add opentelemetry_sdk --features=rt-tokio
cargo add opentelemetry-otlp
```

!!! warning "Telemetry Dependencies"

    This simple use of `cargo add` above assumes the above dependencies may not always work well at latest versions. You might receive multiple versions of `opentelemetry` libs / `tonic` in `cargo tree` (which might not work), and due to different release cycles and pins, you might not be able to upgrade opentelemetry dependencies immediately. For working combinations see for instance the [pins in controller-rs](https://github.com/kube-rs/controller-rs/blob/main/Cargo.toml) + [examples in tracing-opentelemetry](https://github.com/tokio-rs/tracing-opentelemetry/tree/v0.1.x/examples).

Setting up the layer and configuring the `collector` follows fundamentally the same process:

```rust
let otel = tracing_opentelemetry::OpenTelemetryLayer::new(init_tracer());
```

Change our registry setup to use 3 layers:

```diff
-Registry::default().with(logger).with(env_filter).init();
+Registry::default().with(env_filter).with(logger).with(otel).init();
```

However, tracing requires us to have a configurable location of **where to send spans**, the provders needs to be globally registered, and you likely want to set some resource attributes, so creating the actual `tracer` requires a bit more work:

```rust
fn init_tracer() -> opentelemetry_sdk::trace::Tracer {
    use opentelemetry::trace::TracerProvider;
    use opentelemetry_otlp::{SpanExporter, WithExportConfig};
    use opentelemetry_sdk::{runtime, trace::Config};

    let endpoint = std::env::var("OPENTELEMETRY_ENDPOINT_URL").expect("Needs an otel collector");
    let exporter = SpanExporter::builder()
        .with_tonic()
        .with_endpoint(endpoint)
        .build()
        .unwrap();

    let provider = sdktrace::TracerProvider::builder()
        .with_batch_exporter(exporter, runtime::Tokio)
        .with_resource(resource())
        .build();

    opentelemetry::global::set_tracer_provider(provider.clone());
    provider.tracer("tracing-otel-subscriber")
}
```

Note the gRPC address (e.g. `OPENTELEMETRY_ENDPOINT_URL=https://0.0.0.0:55680`) must point to an otlp port on otel collector / tempo / etc. This can point to `0.0.0.0:PORT` if you portforward to it when doing `cargo run` locally, but in the cluster it should be the cluster dns as e.g. `http://promstack-tempo.monitoring.svc:431`.

For some starting resource attributes;

```rust
use opentelemetry_sdk::Resource;
fn resource() -> Resource {
    use opentelemetry::KeyValue;
    Resource::new([
        KeyValue::new("service.name", env!("CARGO_PKG_NAME")),
        KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
    ])
}
```

which can be extended better using the [opentelemetry_semantic_conventions](https://docs.rs/opentelemetry-semantic-conventions/0.26.0/opentelemetry_semantic_conventions/resource/index.html).

For a full setup example for this code see [controller-rs/telemetry.rs](https://github.com/kube-rs/controller-rs/blob/main/src/telemetry.rs).

### Instrumenting
Once you have initialised your registry, you can start adding `#[instrument]` attributes onto functions you want. Let's do `reconcile`:

```rust
#[instrument(skip(ctx))]
async fn reconcile(foo: Arc<Foo>, ctx: Arc<Data>) -> Result<Action, Error>
```

Note that the `reconcile` span should generally be **the root span** in the context of a controller. A reconciliation starting is generally the root of the chain, and since the `reconcile` fn is invoked by the runtime, nothing significant sits above it.

!!! warning "Higher levels spans"

    Do not `#[instrument]` any function that creates a [Controller] as this would create an unintentionally wide ([application lifecycle wide](https://github.com/kube-rs/kube/pull/741#issuecomment-991163664)) span being a parent to all `reconcile` spans. Such a span will be **problematic** to manage.

### Linking Logs and Traces

To link logs and traces we take advantage that tracing data is being outputted to both logs and our tracing collector, and attach the `trace_id` onto our root span:

```rust
#[instrument(skip(ctx), fields(trace_id))]
async fn reconcile(foo: Arc<Foo>, ctx: Arc<Data>) -> Result<Action, Error> {
    let trace_id = get_trace_id();
    if trace_id != TraceId::INVALID {
        Span::current().record("trace_id", field::display(&trace_id));
    }
    todo!("reconcile implementation")
}
```

This part is useful for [Loki] or other logging systems as a way to cross-link from logs to traces.

Extracting the `trace_id` requires a helper function atm:

```rust
pub fn get_trace_id() -> opentelemetry::trace::TraceId {
    use opentelemetry::trace::TraceContextExt as _;
    use tracing_opentelemetry::OpenTelemetrySpanExt as _;
    tracing::Span::current()
        .context()
        .span()
        .span_context()
        .trace_id()
}
```

and it is the only reason for needing to directly add [opentelemetry] as a dependency.

## Adding Metrics

This is the most verbose part of instrumentation because it introduces the need for a [[webserver]], along with data modelling choices and library choices.

There are multiple libraries that you can use here;

- [tikv's prometheus library](https://github.com/tikv/rust-prometheus) :: most battle tested library available, lacks newer features
- [prometheus/client_rust](https://crates.io/crates/prometheus-client) :: official, newish. supports exemplars.
- [measured](https://crates.io/crates/measured) :: very new, client-side cardinality control and memory optimisations

While [controller-rs uses client_rust](https://github.com/kube-rs/controller-rs/blob/main/src/metrics.rs) to support exemplars,
this tutorial will use `tikv/rust-prometheus` for now:

```sh
cargo add prometheus
```

### Registering

We will start creating a basic `Metrics` struct to house two metrics, a histogram and a counter:

```rust
#[derive(Clone)]
pub struct Metrics {
    pub reconciliations: IntCounter,
    pub failures: IntCounterVec,
    pub reconcile_duration: HistogramVec,
}

impl Default for Metrics {
    fn default() -> Self {
        let reconcile_duration = HistogramVec::new(
            histogram_opts!(
                "doc_controller_reconcile_duration_seconds",
                "The duration of reconcile to complete in seconds"
            )
            .buckets(vec![0.01, 0.1, 0.25, 0.5, 1., 5., 15., 60.]),
            &[],
        )
        .unwrap();
        let failures = IntCounterVec::new(
            opts!(
                "doc_controller_reconciliation_errors_total",
                "reconciliation errors",
            ),
            &["instance", "error"],
        )
        .unwrap();
        let reconciliations =
            IntCounter::new("doc_controller_reconciliations_total", "reconciliations").unwrap();
        Metrics {
            reconciliations,
            failures,
            reconcile_duration,
        }
    }
}
```

and as these metrics are measurable entirely from within **`reconcile` or `error_policy`** we can attach the struct to the context passed to the [[reconciler##using-context]].

### Measuring

Measuring our metric values can then be done by explicitly taking a `Duration`  inside `reconcile`, but it is easier to wrap this in a struct that relies on `Drop` with a convenience constructor:


```rust
pub struct ReconcileMeasurer {
    start: Instant,
    metric: HistogramVec,
}

impl Drop for ReconcileMeasurer {
    fn drop(&mut self) {
        let duration = self.start.elapsed().as_millis() as f64 / 1000.0;
        self.metric.with_label_values(&[]).observe(duration);
    }
}

impl Metrics {
    pub fn count_and_measure(&self) -> ReconcileMeasurer {
        self.reconciliations.inc();
        ReconcileMeasurer {
            start: Instant::now(),
            metric: self.reconcile_duration.clone(),
        }
    }
}
```

and call this from `reconcile` with one line:

```rust
async fn reconcile(foo: Arc<Foo>, ctx: Arc<Context>) -> Result<Action, Error> {
    let _timer = ctx.metrics.count_and_measure(); // increments now

    // main reconcile body here

    Ok(...) // drop impl invoked, computes time taken
}
```

and handle the `failures` metric inside your  `error_policy`:

```rust
fn error_policy(doc: Arc<Document>, error: &Error, ctx: Arc<Context>) -> Action {
    warn!("reconcile failed: {:?}", error);
    ctx.metrics.reconcile_failure(&doc, error);
    Action::requeue(Duration::from_secs(5 * 60))
}

impl Metrics {
    pub fn reconcile_failure(&self, doc: &Document, e: &Error) {
        self.failures
            .with_label_values(&[doc.name_any().as_ref(), e.metric_label().as_ref()])
            .inc()
    }
}
```

We could increment the failure metric directly, but we have also made a helper function stashed away that extracts the object name and a short error name as labels for the metric.

This type of error extraction requires an impl on your `Error` type. We use `Debug` here:

```rust
impl Error {
    pub fn metric_label(&self) -> String {
        format!("{self:?}").to_lowercase()
    }
}
```

!!! note "Exemplars linking Logs and Traces"

    In controller-rs (using prometheus_client) we attached our `trace_id` to the histogram metric - through `count_and_measure` - to be able to cross-browse from grafana metric panels into a trace-viewer. See [this comment](https://github.com/kube-rs/controller-rs/pull/72#issuecomment-2335150121) for more info.

### Exposing

For prometheus to obtain our metrics, we require a web server. As per the [[webserver]] guide, we will assume [actix-web].

In our case, we will pass a `State` struct that contains the `Metrics` struct and attach it to the `HttpServer` in `main`:

```rust
HttpServer::new(move || {
    App::new()
        .app_data(Data::new(state.clone())) // new state
        .service(metrics) // new endpoint
    })
```

the `metrics` service is the important one here, and its implementation is able to extract the `Metrics` struct from actix's `web::Data`:

```rust
#[get("/metrics")]
async fn metrics(c: web::Data<State>, _req: HttpRequest) -> impl Responder {
    let metrics = c.metrics(); // grab out of actix data
    let encoder = TextEncoder::new();
    let mut buffer = vec![];
    encoder.encode(&metrics, &mut buffer).unwrap();
    HttpResponse::Ok().body(buffer)
}
```

### What Metrics

The included metrics `failures`, `reconciliations` and a `reconcile_duration` histogram will be sufficient to have prometheus compute a wide array of details:

- reconcile amounts in last hour - `sum(increase(reconciliations[1h]))`
- hourly error rates - `sum(rate(failures[1h]) / sum(rate(reconciliations[1h]))`
- success rates - same rate setup but `reconciliations / (reconciliations + failures)`
- p90 reconcile duration - `histogram_quantile(0.9, sum(rate(reconciliations[1h])))`

and you could then create alerts on aberrant values (e.g. say 10% error rate, zero reconciliation rate, and maybe p90 durations >30s).

The above metric setup should comprise the core need of a **standard** controller (although you may have [more things to care about](https://sirupsen.com/metrics) than our simple example).

!!! note "kube-state-metrics"

    It is possible to derive metrics from conditions and fields in your CRD schema using [runtime flags to `kube-state-metrics`](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/customresourcestate-metrics.md) without instrumentation, but since this is an implicit dependency for operators, it should not be a default.

You will also want resource utilization metrics, but this is typically handled upstream. E.g. cpu/memory utilization metrics are generally available via kubelet's metrics and other utilization metrics can be gathered from [node_exporter](https://github.com/prometheus/node_exporter).

!!! note "tokio-metrics"

    New **experimental** runtime metrics are also availble for the tokio runtime via [tokio-metrics](https://github.com/tokio-rs/tokio-metrics).

### External References

- [Metrics in axum using metrics crate](https://github.com/tokio-rs/axum/tree/143c415955bbd5021e28f493ef7c285de191ffe1/examples/prometheus-metrics)



--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[webserver]: webserver "Web Server"
[reconciler##using-context]: reconciler "The Reconciler"
[//end]: # "Autogenerated link references"
