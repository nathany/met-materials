# Metal by Tutorials — Rust ports

Rust ports of the book's sample projects, following [rust-port-plan.md](../rust-port-plan.md)
(objc2 framework crates + glam). One Cargo workspace; one package per chapter.

Because `final` is a reserved Rust keyword, each chapter's binaries are named
`chNN-final` / `chNN-challenge`.

```sh
cd rust
cargo run --bin ch01-final
cargo run --bin ch01-challenge
```

Run with Metal validation while developing:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 cargo run --bin ch01-final
```

## Chapters

| Package | Book project | Notes |
|---|---|---|
| [01-hello-metal](01-hello-metal/) | ch. 1 playgrounds (final + challenge) | The playground's live view becomes a minimal AppKit app (`NSApplicationDelegate` + `MTKViewDelegate`); includes the raw-`objc_msgSend` workaround for `MDLMesh`'s simd-typed sphere initializer (see `src/simd.rs`) |
