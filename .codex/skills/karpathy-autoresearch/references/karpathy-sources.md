# Karpathy source notes

Sources checked on 2026-06-27:

- `karpathy/autoresearch`: https://github.com/karpathy/autoresearch
- `karpathy/nanochat`: https://github.com/karpathy/nanochat

## `karpathy/autoresearch`

Use these principles when translating autoresearch to software projects:

- Give an agent a small real setup and let it run bounded experiments automatically.
- Keep a fixed runtime budget so experiments are comparable on the same platform.
- Use a single primary metric; in the original LLM setup, validation bits per byte (`val_bpb`) is minimized.
- Restrict the edited surface. The original project keeps data prep/utilities stable, lets the agent edit the training file, and treats `program.md` as human-written "research org code".
- Optimize the instruction/program layer over time, not only the code under test.
- Prefer self-contained setups with few dependencies and reviewable diffs.

Useful adaptation: for non-ML projects, replace `train.py` with the narrow implementation surface and replace `val_bpb` with a deterministic contract metric such as failing checks, latency, memory, cost, or task success rate.

## `karpathy/nanochat`

Use these principles when the project resembles LLM tooling, training, benchmarks, or performance optimization:

- Keep the system minimal, readable, hackable, and end-to-end runnable.
- Prefer one obvious complexity dial where possible. In nanochat, `--depth` controls model scale while related hyperparameters are derived automatically.
- Use speedrun-style scripts as reproducible reference paths.
- Track both quality and efficiency metrics. Relevant nanochat examples include validation bits per byte, CORE score, VRAM, MFU, and tokens/sec.
- Ensure changes are principled across scales, not overfit to one model size or hardware target.
- Provide CPU/MPS/smaller-hardware fallback paths when accessibility matters, but clearly flag weaker expected quality.

## Prompt pattern for experiments

Use this template when instructing an agent or future Codex session:

```text
Read the contract and baseline. Propose one small hypothesis to improve <metric> while obeying <guardrails>. Change only <editableFiles>. Run <eval command>. Keep the patch only if the metric improves or a guardrail is fixed without regressions. Report baseline, result, delta, decision, and next ideas.
```
