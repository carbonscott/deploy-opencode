# Accelerating Scientific Discovery Through AI-Ready Infrastructure

*A strategy for sustainable AI adoption at experimental user facilities*

---

## The Challenge

Scientific facilities across the DOE complex are racing to adopt AI.
The prevailing approaches — fine-tuning foundation models on domain data,
or building custom agent frameworks — are expensive, fragile, and create
dependencies that limit long-term flexibility.

Fine-tuning a model on domain data produces a specialized capability that
is locked to a single model version.  When the next generation of
foundation models arrives — often within months — the fine-tuning
investment must be repeated, along with the evaluation infrastructure
needed to validate the new version.  The cost of re-evaluation can
outweigh the benefit of specialization, especially in scientific domains
where the underlying data and methods evolve continuously.

Building custom agent frameworks (orchestration systems that define
exactly what an AI can and cannot do) creates a different kind of lock-in.
The framework encodes domain logic in a form that is tightly coupled to a
specific AI platform.  When a better platform emerges, the domain logic
must be extracted and re-implemented — a migration cost that grows with
every capability added.

Both approaches share a common failure mode: they invest in layers of the
technology stack that are changing fastest, while underinvesting in the
layer that is most durable and most broadly useful.


## A Three-Layer Strategy for AI Adoption

An AI-augmented scientific workflow has three layers.  The question is not
whether to use AI, but where to invest for the greatest return.

```
┌────────────────────────────────────────────────────────────┐
│  FOUNDATION MODELS                                         │
│                                                            │
│  General-purpose AI models (commercial or open-source).    │
│  These improve rapidly on their own.  Investments here     │
│  depreciate with each model generation.                    │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  ORCHESTRATION PLATFORM                                    │
│                                                            │
│  The system that connects models to tools and manages      │
│  interaction (e.g., Claude Code, OpenCode, or future       │
│  platforms including the American Science Cloud).           │
│  Keep this interoperable and swappable.                    │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  SCIENTIFIC TOOLING AND DATA INFRASTRUCTURE                │
│                                                            │
│  Domain-specific tools, curated databases, automated       │
│  data pipelines, search indexes, and structured domain     │
│  knowledge.  Investments here are durable, portable        │
│  across models and platforms, and accelerate both human     │
│  and AI-driven workflows.                                  │
│                                                            │
│                              ◄── strategic investment      │
└────────────────────────────────────────────────────────────┘
```

**Foundation models** are advancing rapidly without domain-specific
investment.  Each generation is more capable than the last.  When we
provide a current-generation model with well-structured tools and domain
knowledge, it performs well across our scientific use cases without
fine-tuning.  This means our investment automatically benefits from
every model improvement — at no additional cost.

**Orchestration platforms** are the connection layer between models and
tools.  Today we use Claude Code and OpenCode; tomorrow we may use
platforms integrated with the American Science Cloud.  By keeping our
domain logic out of this layer, we can adopt better platforms as they
emerge without rebuilding our capabilities.

**Scientific tooling and data infrastructure** is where durable value
is created.  Automated pipelines that curate and refresh experimental
data.  Search indexes that make documentation discoverable.  Structured
databases that make facility metadata queryable.  Domain knowledge
encoded as portable documentation that any model — current or future —
can consume.  These investments accelerate both human researchers and
AI agents, and they remain valuable regardless of which model or
platform is used.

The key insight is that **better scientific tooling enables both human
and AI-driven discovery.**  A searchable experiment database is useful to
a scientist writing queries at a terminal.  It is equally useful to an
AI agent that translates a natural language question into the same query.
The infrastructure investment pays off in both modes.


## Domain Knowledge That Survives Model Upgrades

A critical challenge in scientific AI is encoding domain expertise —
naming conventions, instrument configurations, data relationships,
operational constraints — in a form that the AI can use effectively.

The prevailing approach is to embed this knowledge into model weights
through fine-tuning.  This creates a capable but inflexible asset: the
knowledge is opaque (encoded in neural network parameters, not readable
by humans), non-portable (locked to one model version), and expensive to
maintain (requires re-training and re-evaluation with each model update).

Our approach is different.  We encode domain knowledge as structured
documentation that accompanies each tool — analogous to the reference
manuals that accompany scientific instruments.  These documents describe
the tool's capabilities, the data schemas it operates on, domain-specific
conventions and terminology, known constraints, and recommended
workflows.

This documentation serves both human researchers and AI agents.  A new
team member reads it to learn how to query the experiment database.  An
AI agent reads the same documentation to construct well-formed queries
on a scientist's behalf.  The documentation is:

- **Readable:** Written in plain text, version-controlled, and
  reviewable by domain experts
- **Portable:** Works with any foundation model, current or future
- **Maintainable:** Updated with a text editor, not a training pipeline
- **Durable:** Coupled to the tool and its data, not to any specific
  model or platform

This is not a theoretical advantage.  In practice, when we upgraded from
one generation of foundation models to the next, every capability in our
deployment improved automatically — because the domain knowledge was
already structured in a form the new model could consume without any
retraining or adaptation.


## Capabilities in Production

This strategy is operational at the Linac Coherent Light Source (LCLS) at
SLAC National Accelerator Laboratory, where approximately fifteen
AI-augmented capabilities serve scientists and engineers across experiment
operations, data analysis, and facility computing.  Each illustrates a
different pattern of AI-ready infrastructure.


### Searchable Scientific Documentation Across Facilities

Scientific documentation — facility guides, operational procedures,
analysis tutorials — is typically scattered across websites, wikis, and
repositories.  Researchers spend significant time searching for
information that exists but is not easily discoverable.

We built a general-purpose documentation indexing tool that creates
full-text search databases from any documentation collection.  Automated
pipelines synchronize with upstream sources (daily for S3DF facility
documentation, weekly for OLCF documentation) and rebuild the search
index.  AI agents use the same search capabilities as human researchers,
adding natural language access and the ability to synthesize information
across multiple search results.

One indexing tool now powers three distinct AI capabilities across two
national laboratory facilities, with the ability to extend to any
additional documentation collection.  The indexing infrastructure operates
continuously whether or not AI is involved — researchers can search
directly at any time.


### Natural Language Access to Experiment Metadata

LCLS generates extensive experimental metadata — run configurations,
detector settings, sample descriptions, operational logbook entries —
stored behind authenticated APIs that are not designed for ad-hoc
analysis.  Scientists frequently need to answer questions that span
multiple data sources: "Which experiments used this detector configuration
with protein crystallography samples?"

We built an automated data pipeline that extracts experiment metadata
every six hours into a structured database containing nine interrelated
tables covering experiments, runs, detectors, logbook entries, and sample
configurations.  The database currently holds approximately 1.3 gigabytes
of curated experimental history.

Scientists can query this database directly using standard tools.  The
AI capability adds natural language access: a researcher asks a question
in plain English, and the system constructs the appropriate database
query, executes it, and interprets the results in context.  Domain
knowledge — LCLS naming conventions, instrument identifiers, data
relationships — is encoded in the portable documentation that
accompanies the tool, not in model weights.


### AI-Augmented HPC Resource Management

The S3DF high-performance computing cluster serves hundreds of
researchers across multiple instruments.  Job scheduling, GPU allocation,
and resource optimization require understanding a complex system with
over 200 nodes, seven partition types, multiple GPU architectures, and
a priority system that balances fairshare, quality-of-service, and
account limits.

The scheduling system already provides command-line tools for querying
cluster state.  What researchers lack is not access to information but
the domain expertise to interpret it.  When a job is pending, the
scheduling system reports a code like "AssocGrpNodeLimit" — which means
the user's research group has reached its allocation cap, not that the
cluster is full.  The difference determines the correct response
(request a higher allocation vs. wait for resources).

Our AI capability wraps the existing scheduling tools with structured
domain knowledge: which commands are reliable, which may fail when
backend services are temporarily unavailable, what the output codes
mean in practice, and what actions are available for each situation.  The
scheduling tools themselves are unchanged — the AI adds interpretation
and actionable guidance that would otherwise require consulting with
facility staff.


### AI-Assisted Beamline Operations

This is our most ambitious capability and the most instructive about how
safety should be implemented in AI-augmented scientific workflows.

LCLS beamlines are controlled through interactive sessions running on
data acquisition nodes.  We developed a bridge that allows an AI agent
to assist with beamline operations — querying instrument positions,
suggesting scan parameters, and (with explicit human approval) executing
commands on beamline hardware.

The safety architecture demonstrates our core principle: **safety
controls should be implemented in infrastructure, not in AI
instructions.**

Infrastructure-level safety is strong and reliable:
- The connection requires a multi-hop secure tunnel through controlled
  network infrastructure — accidental connections are physically
  impossible
- The bridge process must be manually launched by an authorized operator
  in the beamline control session
- Network isolation ensures the AI agent never has direct access to
  beamline hardware

Where we rely on AI-level safety (requiring the model to ask for human
confirmation before executing write commands), we acknowledge this is
weaker and have marked the capability as experimental.  Our roadmap
includes moving these confirmation requirements into the bridge
infrastructure itself — a default-deny architecture where the bridge
refuses write commands unless accompanied by a cryptographic confirmation
token.

This example illustrates an important general principle for AI in
safety-critical scientific environments: the AI should provide judgment
and convenience, while the infrastructure provides safety guarantees.
Model behavior can be influenced but not guaranteed; infrastructure
behavior can be engineered and verified.


## Risk Assessment and Mitigation

We have stress-tested this approach against the strongest objections and
present them transparently.

**Complex multi-source analysis.**  Questions that span multiple data
sources — correlating experiment anomalies with instrument logs and
operational documentation — require the AI to orchestrate queries across
multiple tools in sequence.  Our architecture provides no explicit
workflow graph for this orchestration; the AI coordinates these queries
through in-context reasoning.  This works well for the query-and-
synthesize pattern that dominates scientific analysis.  For workflows
requiring guaranteed execution sequences with checkpointing and error
recovery (e.g., multi-hour automated processing pipelines), explicit
workflow orchestration would be more appropriate — and could be added as
another tool within the same architecture.

**Safety in AI-augmented instrument control.**  As described above, our
beamline control capability currently relies partly on AI-level safety
(model compliance with confirmation instructions) rather than purely
infrastructure-level safety.  This is acknowledged, mitigated by
infrastructure-level network isolation, and actively being addressed
through bridge-level safety mechanisms.  The important point is that our
architecture identifies where safety should live and provides a clear
path to implementing it correctly.

**Scaling to larger tool ecosystems.**  At our current scale of fifteen
capabilities, each AI interaction loads the domain knowledge relevant to
the specific tools being used.  As the ecosystem grows to dozens or
hundreds of capabilities, a routing mechanism is needed to identify which
domain knowledge to load.  This routing is itself a tool — a search index
over capability descriptions — and we have already built the general-
purpose indexing infrastructure that can serve this function.  The
architecture scales within its own principles.

**Performance measurement and feedback.**  We do not yet have systematic
instrumentation for measuring capability quality — tracking which tools
are invoked, whether outputs are correct, and how researchers use the
results.  This is a recognized gap.  The solution is consistent with our
approach: build a logging and analytics tool.  The architecture does not
prevent feedback instrumentation; it simply has not been the priority
to date.


## Strategic Alignment

This approach aligns with several key priorities for AI adoption across
the DOE scientific complex.

**Model-agnostic architecture.**  Because no capability depends on a
specific foundation model, the entire infrastructure benefits
automatically from model improvements.  This is particularly important
in a landscape where model capabilities are advancing rapidly and where
different platforms (commercial, open-source, government-hosted) may be
preferred for different classification levels and data sensitivity
requirements.

**Interoperability with shared platforms.**  The tooling-first approach
produces capabilities that are defined by their tools and data, not by
their AI platform.  This makes them naturally portable to shared
infrastructure such as the American Science Cloud.  The tools, databases,
and domain knowledge documentation can be deployed on any platform that
provides model access and tool execution — which is the fundamental
architecture of modern AI platforms.

**Broad impact across human and AI workflows.**  Every tool built under
this approach serves researchers directly, independent of AI.  The
searchable documentation indexes, the curated experiment databases, the
automated data pipelines — all of these accelerate scientific workflows
whether accessed by a researcher at a terminal or by an AI agent
translating natural language.  This dual-use property means the
infrastructure investment delivers value immediately, not only when AI
capabilities mature.

**Sustainable and maintainable.**  Domain knowledge encoded as readable
documentation can be reviewed, updated, and maintained by domain experts
using familiar tools (text editors, version control).  There is no
dependency on specialized AI training infrastructure, no need for
evaluation pipelines, and no risk of catastrophic knowledge loss when
a model version is retired.  A new team member can read the same
documentation the AI reads and understand exactly what the system knows
and how it operates.

**Reproducible across facilities.**  The pattern — build a tool, document
it for AI consumption, connect it to an orchestration platform — is
reproducible.  Other facilities facing similar challenges (making
experimental data queryable, making facility documentation searchable,
augmenting instrument operations) can apply the same approach with their
own tools and domain knowledge.  The architecture is a template, not a
monolith.


## Summary

The most effective AI strategy for scientific computing is not to build
AI agents.  It is to build the scientific infrastructure that makes AI
agents effective — and that simultaneously accelerates human-driven
research.

Automated data pipelines that keep experimental metadata current.  Search
indexes that make documentation discoverable.  Structured domain
knowledge that can be consumed by any foundation model, current or
future.  Safety architectures that provide infrastructure-level
guarantees rather than relying on model behavior.

This approach is operational today at LCLS, serving researchers across
experiment operations, data analysis, and facility computing.  It has
survived model upgrades without retraining, platform transitions without
rebuilding, and honest critical review without requiring fundamental
changes to its architecture.

The investment is in scientific tooling — and the tooling is worth
building regardless of AI.

---

*This document reflects operational experience from the LCLS AI-augmented
workflow deployment at SLAC National Accelerator Laboratory, where
approximately fifteen capabilities serve scientists and engineers across
the Linac Coherent Light Source.  The deployment operates on the S3DF
high-performance computing cluster using general-purpose foundation
models with no fine-tuning.  The deployment serves experimental science
workflows, not large-scale simulation.*
