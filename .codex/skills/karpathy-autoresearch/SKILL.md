---
name: karpathy-autoresearch
description: Karpathy-inspired autonomous improvement loops for Codex projects. Use when asked to improve a repository, run product/code research, create eval-driven experiments, build a nanochat/autoresearch-style harness, tune an existing Karpathy eval harness, or iteratively optimize software with measurable metrics, guardrails, small editable surfaces, and keep-or-revert experiment logs.
---

# Karpathy AutoResearch

Apply Karpathy's `autoresearch` and `nanochat` ideas to ordinary Codex projects: define a tiny research world, let agents propose and test bounded changes, keep only metric-improving work, and leave an auditable trail.

## Core workflow

1. **Map the project.** Read README, package metadata, tests, existing eval harnesses, and any project instructions. Identify the product goal in one sentence.
2. **Define the research contract.** Write or reuse an eval with:
   - `editableFiles`: the smallest files an experiment may change.
   - `readOnlyFiles` / `contextFiles`: files for grounding.
   - `guardrails`: safety, style, secrets, and scope constraints.
   - `metric`: one primary scalar with direction (`minimize` or `maximize`).
3. **Establish a baseline.** Run the eval once before modifying code. Record command, metric, failures, runtime, and environment limitations.
4. **Generate hypotheses.** Prefer small, falsifiable changes: one idea per branch/patch. Rank by expected metric movement, risk, and reviewability.
5. **Run bounded experiments.** Edit only the allowed surface, run the same eval command, compare against baseline, and inspect diffs.
6. **Keep or revert.** Keep changes only when they improve the metric or fix guardrails without regressions. Revert failed speculative edits promptly.
7. **Log findings.** Summarize hypothesis, patch, metric delta, decision, and follow-up ideas in the PR/commit body or a project eval log when one exists.

## Codex execution rules

- Keep experiment patches small enough to review.
- Prefer deterministic local checks over subjective judgments.
- Treat wall-clock budgets as part of the metric when optimizing speed or cost.
- Preserve user-facing behavior unless the experiment explicitly targets it.
- Do not broaden editable surfaces just because an adjacent file is convenient; update the contract deliberately.
- Never hide failing checks. Classify failures as metric regressions, guardrail failures, or environment limitations.
- When spawning parallel agents is allowed by the user, split experiments by disjoint write sets and compare results against the same baseline.

## Repo patterns to look for

- Existing `karpathy:*` npm scripts, `evals/karpathy/*.json`, or product-research CLIs.
- A single check script that outputs a scalar such as `failing_checks`, latency, pass rate, tokens/sec, cost, or benchmark score.
- A narrow product surface like docs + bootstrap scripts, one training script, or one service module.

## When building a harness

Use a JSON contract similar to:

```json
{
  "id": "project-contract",
  "productName": "Project improvement contract",
  "branchPrefix": "karpathy/",
  "editableFiles": ["README.md", "src/main.ts"],
  "readOnlyFiles": ["scripts/check-contract.mjs"],
  "contextFiles": ["package.json"],
  "guardrails": ["Do not introduce secrets", "Keep public CLI behavior documented"],
  "eval": {
    "command": "node",
    "args": ["scripts/check-contract.mjs"],
    "metric": { "name": "failing_checks", "direction": "minimize" },
    "successMetricValue": 0,
    "timeBudgetMinutes": 3,
    "timeoutMinutes": 10
  }
}
```

## Reference material

Read `references/karpathy-sources.md` when you need source-grounded details from Karpathy's GitHub repositories, especially for adapting `autoresearch`/`nanochat` concepts or explaining why a workflow uses fixed budgets, single-file edit surfaces, depth sweeps, bits-per-byte metrics, or speedrun-style leaderboards.
