# Portable GPU bot compute

**Status:** researched, experiment planned, 2026-09-19. No GPU bot backend is
implemented or measured. Local evaluation costs $0. Campaign production remains
the immediate priority; GPU support is an optional scale capability.

## Scope and current evidence

Evaluate GPU capacity for batched bot perception and optional local model
inference while keeping Windows, Linux and macOS support. The Rust server owns
outcomes; Godot already renders on the GPU. A headless server must remain useful
without a GPU, paid API or installed vendor compute toolkit.

Current rule bots run through `GameSession::tick_messages`, `Bot::intent` and
`navigation::Navigator`. They are not neural models. The separate `agents/brain`
provider currently uses local rules or remote decisions, not local GPU inference.
GPU acceleration cannot make those existing remote calls run locally without a
compatible model, licensed weights and a verified inference implementation.

The [navigation receipt](height-aware-navigation.md#integration-follow-up) records
12,000-tick offline CPU samples at 16/64/128 bots, with repeated complete traces.
They leave tick-budget headroom, but do not isolate perception cost or measure GPU
benefit. Establish that profile before choosing a kernel. Avoid treating an
all-pairs algorithm as necessary work if spatial queries remove most candidates.

## Technology findings

Official documentation and latest non-prerelease release metadata checked
2026-09-19. These are candidates, not new project pins or dependencies.

| Option | Current release checked | Fit and limitation |
|---|---|---|
| [CubeCL](https://github.com/tracel-ai/cubecl) | [0.10.0](https://github.com/tracel-ai/cubecl/releases/tag/v0.10.0) | Rust kernel language with Vulkan, Metal, WebGPU, CUDA and HIP paths. First candidate under the existing Rust policy. Use checked launches; verify generated code against the workspace's unsafe-code prohibition. |
| [wgpu](https://github.com/gfx-rs/wgpu) | [30.0.1](https://github.com/gfx-rs/wgpu/releases/tag/v30.0.1) | Native Rust GPU API over Vulkan, Metal and DirectX 12. Direct WGSL kernels are an alternative if CubeCL adds unsuitable complexity; that would require an explicit, narrow shader-language decision. |
| [Burn](https://github.com/tracel-ai/burn) | [0.21.0](https://github.com/tracel-ai/burn/releases/tag/v0.21.0) | Candidate for an actual trained local policy, not a dependency needed for ordinary rule bots. Verify model operations, weights and backend compatibility first. |
| [Slang](https://github.com/shader-slang/slang) | [2026.18](https://github.com/shader-slang/slang/releases/tag/v2026.18) | Portable shader language/compiler. Adds a language and compiler; its WGSL target remains work in progress. No reason yet to adopt it here. |
| [Mojo](https://mojolang.org/docs/requirements/) | 1.1.0 documentation | Supports NVIDIA, AMD and Apple GPU programming; native Windows is not supported and Windows uses WSL. Does not fit the current shipping/toolchain constraints. |
| [Triton](https://github.com/triton-lang/triton/releases/tag/v3.8.0) / [TileLang](https://github.com/tile-ai/tilelang) | 3.8.0 / 0.1.14 | Useful specialized ML kernel ecosystems, but introduce Python-oriented tooling without a current model/kernel requirement. Not selected for this Rust game. |
| [CUDA Rust](https://developer.nvidia.com/blog/introducing-cuda-rust-two-tracks-for-writing-gpu-kernels/) | September 2026 announcement | cuTile Rust and cuda-oxide target NVIDIA. Neither supplies the required AMD/Apple portability; not the default compute path. |

Released 0.x libraries are not promises of stable APIs. CubeCL selects compatible
backend versions; do not force the latest standalone wgpu into its dependency
graph. Verify actual adapter capabilities, drivers, minimum Rust version, release
notes, transitive licenses and build requirements in the experiment. A supported
backend is not proof that every device from a vendor works.

## Bounded experiment

1. Profile representative 16/64/128-bot matches, then a deliberately larger stress
   case. Separate perception, routing, simulation, spawn selection and encoding.
   Use current maps and captured inputs, including dense fights and partial cover.
2. Select one measured batch, initially visibility/candidate scoring if the
   profile justifies it. Preserve authoritative geometry and the CPU reference.
   Compare improved CPU queries with GPU batching, not only naive all-pairs CPU.
3. Use an isolated optional implementation before changing normal server builds.
   Check empty/oversized batches, buffer bounds, non-finite data, device loss,
   allocation failure and unsupported adapters. Keep required CI GPU-free.
4. Measure upload, dispatch, synchronization, readback and total result latency,
   cold initialization and warm operation separately. Include memory use, batch
   size, backend/driver identity and repeated samples. Run both headless and with
   Godot rendering on the same GPU; an integrated GPU shares memory and power.
5. Compare decisions with the CPU reference on edge cases and recorded matches.
   Define numeric tolerance where appropriate and stable tie handling. Never
   infer cross-device determinism from a same-device trace repeat. Preserve the
   canonical CPU replay test; record backend/model identity for accelerated runs.

The live tick must not synchronously wait for an optional GPU worker. Tag results
with source tick and map/roster generation; bound queues, discard stale output
and use CPU behavior when work fails or misses its deadline. AI acceleration
supplies intent through the same action path. It does not move combat authority
to a client or give external agents hidden state.

## Adoption decision and evidence

Adopt only if representative end-to-end measurements improve available tick
headroom or make a useful local policy feasible, with acceptable render impact,
verified behavior and reliable fallback. Record the workload crossover rather
than enabling GPU work for a handful of cheap decisions. Keep CPU defaults for
ordinary hosts until those results justify another choice. Do not add dependency
weight solely to keep a GPU busy.

Publish measurements in this plan, including unsuccessful cases and actual
NVIDIA/AMD/Apple hardware coverage. GPU kernel timing alone is insufficient.
No protocol change, cloud deployment, hardware purchase or paid model call is
needed for this research. Local inference and the later
[Inheritance strategy benchmark](inheritance-benchmark.md) are separate follow-on
workloads with their own correctness and evaluation contracts.
