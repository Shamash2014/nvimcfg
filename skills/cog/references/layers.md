# layers — separation of concerns

not "chat with tool calling". AI-native cognitive OS.

four orthogonal axes. each replaceable without touching the others.

```
┌─────────────────────────────────────────────────────────────┐
│  L4  KNOWLEDGE LAYER          domain-specific. pluggable.   │
│      • system_prompts (vertical)                            │
│      • RAG indices                                          │
│      • knowledge graphs                                     │
│      • proprietary datasets                                 │
│      • domain heuristics                                    │
├─────────────────────────────────────────────────────────────┤
│  L3  CONTROL LAYER            orchestration. vendor-free.   │
│      • stage orchestration / gates / mutation scheduler    │
│      • prompt versioning                                    │
│      • routing (tier → model)                               │
│      • eval gate / promotion                                │
│      • observability + trace                                │
├─────────────────────────────────────────────────────────────┤
│  L2  CONTRACT LAYER           data shape. process-free.     │
│      • task / subtask / result / eval JSON schemas          │
│      • corridor + criteria + metrics fields                 │
│      • prompt_version registry                              │
├─────────────────────────────────────────────────────────────┤
│  L1  REASONING LAYER          model-agnostic. swappable.    │
│      • LLM calls (haiku / sonnet / opus / OSS / ...)        │
│      • tool execution                                       │
│      • embedding + retrieval primitives                     │
└─────────────────────────────────────────────────────────────┘
```

## what is separated from what

| separation                       | enforced by                                    |
|----------------------------------|------------------------------------------------|
| intelligence  ≠  domain          | L1 + L3 know nothing about vertical. L4 only. |
| reasoning  ≠  data representation| L2 contracts. JSON in/out. no string mixing.  |
| control  ≠  model vendor         | L3 routes by tier; model identity is config.  |
| knowledge  ≠  execution          | L4 served via RAG/KG; L1 just consumes.       |

## consequence

- swap vendor → change L1 config. zero L2/L3/L4 changes.
- swap vertical → swap L4. zero L1/L2/L3 changes.
- harden reasoning → tighten L2 contracts. all layers benefit.
- new feedback signal → L3 routes it into eval. no new product.

## every user input = training signal

input channel does not matter. chat / API / webhook / UI / cron — all flow through L2 as `subtask.json`. all generate `result.json`. all enter eval pool. all feed `meta_learning` candidate generation.

static software → adaptive cognitive infrastructure.

## moat

not the model. not the prompts. not the vertical.

the **infrastructure**: orchestration + contracts + eval datasets + feedback loops + accumulated operational knowledge across L2/L3.

models commoditize in months. L2/L3/L4 compound over years.
