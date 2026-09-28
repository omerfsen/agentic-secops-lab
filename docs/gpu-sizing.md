# GPU sizing

Written against an **RTX 4080 Super (16 GB, Ada / SM89)**, since that's the card this
was worked out on. The reasoning generalises; the numbers don't.

## The constraint

A 30B-parameter checkpoint is roughly **60 GB in BF16**. The 4-bit builds land around
**17–18 GB** — still over 16 GB. So the 30B-A3B Nemotron models do not fit fully in
VRAM on this card.

> An earlier draft of these notes said Nemotron 3 Nano needs "about 24 GB in BF16".
> That was wrong by more than half. The corrected figures are above.

## Options

### 1. Nemotron 3 Nano or 3.5 Lightning with expert offload

llama.cpp or Ollama, 4-bit GGUF, MoE experts spilled to system RAM. Only ~3B
parameters are active per token, so it stays usable — roughly 12 tok/s with offload.
Give the VM **64 GB RAM** for this.

Best choice if you specifically want to run *Nemotron*.

### 2. A smaller model that fits entirely in VRAM

Nemotron Nano 2 9B in FP8 is about **9–10 GB**, and Ada has native FP8 tensor cores,
so it runs fast with room left for KV cache. Any 7–9B model in FP8 works the same way.

Best choice if you want responsiveness and can accept a weaker model.

### 3. NVFP4 — doesn't help here

Ada has **no FP4 tensor cores**; that's Blackwell. vLLM will load NVFP4 checkpoints on
Ada, but as weight-only compression through the Marlin kernel, with a performance
warning. The Nano NVFP4 weights alone are estimated at ~16.8 GB, so it doesn't even
solve the capacity problem.

## NIM licensing

NIM for LLMs *does* list the RTX 4080 16 GB — but **NVIDIA AI Enterprise does not
cover GeForce cards**, so this is development-only, and the Nemotron 3 NIM profiles
target datacentre GPUs regardless.

Use **vLLM** or **llama.cpp** instead. Run the embedding and reranking models on CPU:
the LLM will own the VRAM, and those models are small enough that CPU inference is
acceptable for a lab.

## What the GPU doesn't affect

Everything else in the stack — RKE2, Rancher, NeuVector, OpenShell, NemoClaw, the NeMo
agent pieces — is CPU work. The GPU decision only touches the model tier.

## Scaling up

| card | what changes |
|---|---|
| 24 GB (4090 / L4) | Nano or Lightning at 4-bit fits in VRAM; no offload |
| 48 GB (A6000 / L40S) | comfortable headroom, plus retrieval NIMs on the same card |
| 80 GB (H100 / A100) | Nemotron Super becomes viable as the planner |
| 8×H100 or better | Nemotron 3 Ultra as designed |
