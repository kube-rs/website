# Profiling

## Local CPU Profiling with Samply

Using [samply](https://github.com/mstange/samply) we can run kube applications to generate cpu profiles for the [firefox profiler](https://profiler.firefox.com/).

The documentation above is canonical, but here's a tiny TL;DR:

1. [build/install samply](https://github.com/mstange/samply#installation)
2. Linux: provide [necessary perf_ kernel parameters](https://github.com/mstange/samply#description)
3. create a profiling profile (debug symbols in release mode)

```toml
[profile.profiling]
inherits = "release"
debug = true
```

4. `cargo build --profile profiling myapp`
5. `samply record ./target/profiling/myapp`
6. wait for myapp to run code you wish to profile, then terminate it
7. `samply load profile.json` (automatic on termination)
