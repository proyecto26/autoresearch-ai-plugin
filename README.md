# 🔬 Autoresearch AI Plugin

> **Autonomous Experiment Loops for Claude Code — Let AI optimize while you sleep**

Edit code → commit → run benchmark → measure metric → keep improvement or revert → **repeat forever**.

Works for **any optimization target**: LLM training loss, test speed, bundle size, build time, Lighthouse scores, and more.

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) and [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch).

## 🧰 Skills

This plugin provides two skills that work together. **Autoresearch** is the core engine (works for any metric), and **Autoresearch ML** extends it with GPU-specific templates for LLM training.

### 🔄 **1. Autoresearch (The Optimizer)**
*Domain-agnostic autonomous experiment loop.*
- **Edit → Measure → Keep/Discard**: Autonomous cycle that edits code, runs benchmarks, and keeps only improvements.
- **Context-Resilient**: State persists in `autoresearch.jsonl` — survives context resets and session restarts.
- **Confidence Scoring**: MAD-based statistical analysis separates real improvements from measurement noise.
- **Any Metric**: Test speed, bundle size, build time, Lighthouse scores, memory usage — if you can measure it, you can optimize it.

### 🧠 **2. Autoresearch ML (The Researcher)**
*Specialized for LLM training with NVIDIA GPUs. Extends the core Autoresearch skill.*
- **Ready-to-Use Template**: Complete LLM pretraining setup based on Karpathy's autoresearch (GPT + Flash Attention + MuonAdamW).
- **GPU-Optimized**: Tuned for NVIDIA GPUs (RTX 4090/5090, A100, H100) with CUDA troubleshooting and OOM recovery.
- **Fixed Time Budget**: Every experiment runs for exactly 5 minutes — all results are directly comparable.
- **Bits Per Byte**: Vocab-size-independent metric (`val_bpb`) enables fair comparison across architectures.

---

## 🚀 Quick Start

### Prerequisites

- **Git** — experiments use git commit/revert for state management
- **For ML skill:** NVIDIA GPU with 16GB+ VRAM, CUDA 12.0+, Python 3.10+, [uv](https://astral.sh/uv)

### Installation

#### Option 1: Clone and Copy (Recommended)

```bash
git clone https://github.com/proyecto26/autoresearch-ai-plugin.git
cp -r autoresearch-ai-plugin/skills/* .claude/skills/
```

#### Option 2: Git Submodule

Add as a submodule for easy updates:

```bash
git submodule add https://github.com/proyecto26/autoresearch-ai-plugin.git .claude/autoresearch-ai-plugin
```

Then reference skills from `.claude/autoresearch-ai-plugin/skills/`.

#### Option 3: Claude Code Plugin (Local)

Test with Claude Code's plugin system:

```bash
claude --plugin-dir /path/to/autoresearch-ai-plugin
```

#### Option 4: CLI Install

Use [npx skills](https://github.com/vercel-labs/skills) to install skills directly:

```bash
# Install all skills
npx skills add proyecto26/autoresearch-ai-plugin

# Install specific skills
npx skills add proyecto26/autoresearch-ai-plugin --skill autoresearch autoresearch-ml

# List available skills
npx skills add proyecto26/autoresearch-ai-plugin --list
```

#### Option 5: Fork and Customize

1. Fork this repository
2. Customize skills for your specific needs (add new metrics, change templates)
3. Clone your fork into your projects

### Usage Examples

**"Run autoresearch to optimize my test suite"**
> Triggers **Autoresearch** to set up a benchmark loop, measure test runtime, and iteratively optimize your test configuration.

**"Start an experiment loop to reduce bundle size"**
> Triggers **Autoresearch** to measure your build output and autonomously try tree-shaking, code splitting, and dependency optimizations.

**"Set up ML autoresearch with my RTX 5090"**
> Triggers **Autoresearch ML** to copy the training assets, prepare data, and begin autonomous LLM pretraining experiments.

**"Optimize val_bpb autonomously overnight"**
> Triggers **Autoresearch ML** to run 5-minute training experiments in a loop, keeping architecture and hyperparameter improvements.

---

## ⚙️ How It Works

```
┌─────────────────────────────────────────────────┐
│                  SETUP PHASE                     │
│  Define goal, metric, command, files in scope    │
│  Create autoresearch.md + autoresearch.sh        │
│  Run baseline → Record in autoresearch.jsonl     │
└──────────────────────┬──────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────┐
│              EXPERIMENT LOOP (forever)            │
│                                                   │
│  1. Read past results + autoresearch.md           │
│  2. Choose experimental change                    │
│  3. Edit files → git commit                       │
│  4. Run: bash autoresearch.sh                     │
│  5. Parse METRIC name=value lines                 │
│  6. Run autoresearch.checks.sh (if exists)        │
│  7. Improved? → KEEP commit                       │
│     Worse?    → git revert                        │
│  8. Log to autoresearch.jsonl                     │
│  9. Update autoresearch.md with learnings         │
│                                                   │
│  ↻ Repeat                                         │
└─────────────────────────────────────────────────┘
```

**Context resets?** No problem. `autoresearch.jsonl` + `autoresearch.md` contain everything needed to resume.

---

## 📋 Session Files

| File | Purpose |
|------|---------|
| `autoresearch.md` | Living session doc — goal, metrics, scope, learnings |
| `autoresearch.sh` | Benchmark script outputting `METRIC name=value` lines |
| `autoresearch.checks.sh` | Optional correctness checks (tests, lint, types) |
| `autoresearch.jsonl` | Append-only experiment log (survives restarts) |
| `autoresearch.ideas.md` | Optional backlog of experiment ideas |

---

## 🖥️ ML Training Assets

The `autoresearch-ml` skill includes a complete LLM pretraining setup in `assets/`:

| File | Role |
|------|------|
| `prepare.py` | Data download, BPE tokenizer training, dataloader with best-fit packing |
| `train.py` | GPT model with Flash Attention 3, RoPE, sliding window attention, MuonAdamW |
| `program.md` | Self-contained agent instructions for the autonomous ML loop |
| `pyproject.toml` | Python dependencies (PyTorch 2.9.1 + CUDA 12.8) |

**GPU Requirements:** NVIDIA GPU with 16GB+ VRAM (RTX 4090, RTX 5090, A100, H100).

---

## 📂 Structure

```
autoresearch-ai-plugin/
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest
└── skills/
    ├── autoresearch/                # Generic experiment loop
    │   ├── SKILL.md                 # Core skill — edit/measure/keep/discard cycle
    │   ├── scripts/
    │   │   ├── parse-metrics.sh     # Extract METRIC lines from benchmark output
    │   │   └── log-experiment.sh    # Append results to autoresearch.jsonl
    │   ├── references/
    │   │   ├── confidence-scoring.md  # MAD-based noise analysis
    │   │   └── best-practices.md      # Benchmark tips, experiment strategies
    │   └── examples/
    │       ├── autoresearch.sh      # Example benchmark script
    │       ├── autoresearch.checks.sh # Example correctness checks
    │       └── autoresearch.md      # Example session document
    └── autoresearch-ml/             # ML/GPU specialization (extends autoresearch)
        ├── SKILL.md                 # ML skill — GPU setup, training workflow
        ├── references/
        │   └── gpu-training-guide.md  # CUDA config, OOM fixes, perf tuning
        └── assets/
            ├── prepare.py           # Data prep (download, tokenizer, dataloader)
            ├── train.py             # GPT model + training loop
            ├── program.md           # Agent instructions for ML loop
            └── pyproject.toml       # Python deps (PyTorch + CUDA)
```

---

## 🤝 Contributing

Autoresearch AI grows with the community. Ideas for new optimization domains, better confidence scoring, or additional templates? Please open a PR!

## Credits

- [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) — Original autonomous ML research loop
- [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) — Generalized experiment loop for Pi

## Happy researching 💯
Made with ❤️

<img width="150px" src="https://avatars0.githubusercontent.com/u/28855608?s=200&v=4" align="right">
