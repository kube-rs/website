# Guides and Tutorials

List of third party guides and tutorials for using the `kube-rs` that holds up to scrutiny.

| Title | Year | Use |
| ----- | ---- | --- |
| [Writing a Kubernetes Scheduler in Rust](https://blog.appliedcomputing.io/p/writing-a-kubernetes-scheduler-in) | 2023 | Scheduler PoC |
| [Writing a Kubernetes Operator](https://metalbear.co/blog/writing-a-kubernetes-operator) | 2023 | Operator with [extension api-server](https://kubernetes.io/docs/tasks/extend-kubernetes/setup-extension-api-server/) |
| [Oxidizing the Kubernetes operator](https://www.pavel.cool/rust/rust-kubernetes-operators/) | 2021 | Controller guide with finalizers, state machines
| [A Rust controller for Kubernetes](https://blog.frankel.ch/start-rust/6/) | 2021 | Introductory; project setup + api use |

## Presentations

| Title | Source | Content |
| ----- | ------ | ------- |
| [Kubernetes Controllers in Rust: Fast, Safe, Sane](https://www.youtube.com/watch?v=rXS-3hFYVjc) | KubeCon EU 2024 | Controller building from Linkerd POV |
| [Rust operators for Kubernetes](https://www.youtube.com/watch?v=65pyIeLtd5Y) | PlatformCon 2023 | Rust benefits + kubebuilder comparisons |
| [Introduction to rust operators for Kubernetes](https://www.youtube.com/watch?v=feBYxeO-3cY) | Cloud Native Skunkworks 2023 | Introductory runtime structuring |
| [Lightning Talk: Talking to Kubernetes with Rust](https://www.youtube.com/watch?v=Kp6GQjZixPE) | KubeCon EU 2023 | Introductory; api usage |
| [Why the future of the cloud will be built on Rust](https://www.youtube.com/watch?v=BWL4889RKhU) | Cloud Native Rust Day 2021 | Cloud History + Linkerd + Rust Ecosystem Overview |
| [The Hidden Generics in Kubernetes' API](https://www.youtube.com/watch?v=JmwnRcc2m2A) | KubeCon Virtual 2020 | Early stage kube-rs presentation on apimachinery + client-go translation |

## AI Agents

!!! warning "Generative AI Generates Errors"

    Please be skeptical with output from AI tools or agents. They sound confident, while frequently presenting severely misleading errors, and often erase the sources. Do not be surprised if its solutions turn out to be total nonsense.

    Rust documentation and kube documentation is already extensive. Consider searching [docs.rs/kube](https://docs.rs/kube/latest/kube/), [kube.rs](https://kube.rs/), and [kube/discussions](https://github.com/kube-rs/kube/discussions) for important context.


| Title | Provider | Description |
| ----- | ------ | ------- |
| [kube-rs Guru](https://gurubase.io/g/kube-rs) | Gurubase.io | kube-rs Guru is a kube-rs focused AI to answer user queries based on the data on kube-rs documentation. |
