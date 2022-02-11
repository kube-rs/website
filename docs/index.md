# kube-rs
<!-- rewrite selling points here -->

A [Rust](https://rust-lang.org/) client for [Kubernetes](http://kubernetes.io) in the style of a more generic [client-go](https://github.com/kubernetes/client-go), a runtime abstraction inspired by [controller-runtime](https://github.com/kubernetes-sigs/controller-runtime), and a derive macro for [CRDs](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) inspired by [kubebuilder](https://book.kubebuilder.io/reference/generating-crd.html). Hosted by [CNCF](https://cncf.io/) as a [Sandbox Project](https://www.cncf.io/sandbox-projects/)

These crates build upon Kubernetes [apimachinery](https://github.com/kubernetes/apimachinery/blob/master/pkg/apis/meta/v1/types.go) + [api concepts](https://kubernetes.io/docs/reference/using-api/api-concepts/) to enable generic abstractions. These abstractions allow Rust reinterpretations of reflectors, controllers, and custom resource interfaces, so that you can write applications easily.

<!-- TODO: use an overrides page for home https://github.com/squidfunk/mkdocs-material/blob/9655c3a92471f261533d48b8611a8d24dbfebb13/src/overrides/home.html via https://github.com/squidfunk/mkdocs-material/blob/master/docs/index.md -->

[:fontawesome-solid-book: Getting Started](getting-started){ .md-button align=left } [:fontawesome-brands-discord: Community](https://discord.gg/tokio){ .md-button align=left } [:material-language-rust: Crates](https://crates.io/crates/kube){ .md-button align=left } [:material-github: Github](https://github.com/kube-rs){ .md-button align=left }

<!-- adopters here? -->
