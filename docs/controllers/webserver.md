# Web Server

This is a WIP document.

## Actix-web

Now that we have a more stable release chain of [actix-web] (version 4 is out), it is easier to write guides, and will use this heavily battle tested web-framework.

```sh
cargo add actix-web
```

!!! warning "Heavy Weight Framework"

    The `actix-web` crate is fairly heavy-weight for just exposing metrics. For a simpler web framework that we have partial support for, consider [axum] and our [version-rs] application using it.

### Usage

This document is **unfinished** so we refer to [controller-rs] which is a full-featured example of using [actix-web] with [kube].

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
