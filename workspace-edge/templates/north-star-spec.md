# How the research agent uses this template

Use this at **project kickoff**, before the Superior Architecture scaffold is seeded, to
produce the operator's north-star specification for a new project.

**The flow:**

1. Operator (or the research agent, interviewing the operator) fills the **Project Input**
   block below.
2. Generate with the **Reusable Prompt** (full, 28 required sections) — or the **Short
   Version** when a faster/cheaper pass is enough. The Short Version is a self-contained
   paste-ready prompt; its overlap with the full version is intentional, do not dedupe it.
3. Append **add-ons** as needed: *Technical* (system-design depth), *Product* (requirements
   depth), *Adversarial* (failure analysis depth). They compose — any subset works.
4. The output lands verbatim at `projects/{{PROJECT_SLUG}}/notes/{{PROJECT_SLUG}}-north-star.md`
   with frontmatter `type: north-star-spec, status: unprocessed`.
5. The research agent then distills it: charter Mission first, then
   `notes/SUPERIOR_ARCHITECTURE.md` synthesis. Promotion into the repo stays gated through
   `{{DOCS_DIR}}/KNOWLEDGE_STAGING.md` → `RESEARCH_TRANSFER.md` → `TASKS.md`.
   **The spec and the north-star doc never enter the repo.**

Raw spec sections are never work orders.

---

# North Star Specification Template

Use this template to generate a detail-rich North Star Specification for any future project.

The template is designed for downstream LLM processing, product architecture, technical planning, safety/privacy review, implementation roadmapping, and later trimming. It intentionally asks for dense, structured output.

---

# Reusable Prompt

```markdown
You are a senior product architect, systems designer, technical strategist, adversarial reviewer, privacy/safety architect, and implementation planner.

Your task is to create a deeply detailed **North Star Specification** for the following project.

The output will be used for future LLM processing, product planning, system architecture, agent workflows, implementation roadmapping, risk review, and downstream trimming. Therefore, make it **data-rich, explicit, structured, redundant where useful, and implementation-aware**.

Do not write a pitch deck. Do not write marketing copy. Do not write vague strategy. Produce a serious foundational specification that defines what the project must become if it is to be truly excellent, durable, scalable, trustworthy, and hard to copy.

Assume ambitious long-term software, model, hardware, and infrastructure capabilities, but remain realistic about physics, human behavior, regulation, privacy, economics, operational complexity, safety, latency, trust, and data quality.

---

# Project Input

## Project Name

[INSERT PROJECT NAME]

## Short Description

[DESCRIBE THE PROJECT IN 3-10 SENTENCES]

## Target Users

[DESCRIBE PRIMARY USERS, SECONDARY USERS, EDGE CASE USERS, EXCLUDED USERS IF RELEVANT]

## Core User Problem

[WHAT PAIN, NEED, DESIRE, RISK, OPPORTUNITY, OR BEHAVIOR DOES THIS ADDRESS?]

## Desired Experience

[DESCRIBE HOW THE PRODUCT SHOULD FEEL WHEN IT WORKS PERFECTLY]

## Current Idea / Concept

[DESCRIBE CURRENT PRODUCT IDEA, FEATURES, WORKFLOW, SYSTEM, APP, SERVICE, HARDWARE, PLATFORM, ETC.]

## Known Constraints

[PLATFORMS, BUDGET, HARDWARE, REGULATORY, TECHNICAL, MARKET, PRIVACY, LATENCY, SAFETY, TRUST, BUSINESS, DATA, ORGANIZATIONAL, ETC.]

## Dream Assumption

Assume ambitious long-term capabilities, but stay realistic. Do not hand-wave away hard problems with “AI will solve it.” Distinguish between:

```text
possible now
possible with near-term engineering
possible with specialized infrastructure
possible only with future hardware/platform shifts
unlikely because of human behavior, regulation, economics, or trust
```

## Explicit Non-Goals

[WHAT SHOULD THIS NOT BECOME? WHAT WOULD VIOLATE THE PRODUCT'S PURPOSE?]

## Open Questions

[OPTIONAL: QUESTIONS, RISKS, UNCERTAINTIES, UNKNOWN DEPENDENCIES]

---

# Required Output Format

Create a complete file-style Markdown document titled:

```text
[PROJECT NAME] North Star Specification
```

Use clear headings, tables, bullet lists, YAML-style schemas, enumerations, metrics, decision rules, failure modes, and operational requirements.

The spec must be dense enough that another LLM could later use it to generate:

```text
product requirements
technical architecture
data models
MVP plan
evaluation plan
safety/privacy review
implementation roadmap
agent workflows
investor memo
design principles
test suite
simulation suite
risk register
operational playbook
```

Do not omit important content for readability. This document will be trimmed downstream.

---

# Required Sections

## 1. Executive Definition

Define the project in one precise paragraph.

Also provide:

```text
The project is:
The project is not:
The highest-level ambition is:
The product succeeds when:
The product fails when:
```

Avoid generic language. Be concrete.

---

## 2. North Star Thesis

Describe what would make the project truly revolutionary, category-defining, or unusually durable.

Include:

```text
the deep user transformation
why existing solutions are insufficient
what must become true for this to matter
what the project must master
what the product must never compromise
what would make users choose it repeatedly
what would make it difficult to copy
```

Use compact but high-density writing.

---

## 3. Core Experience Principles

List 8-15 core principles governing the experience.

For each principle, use:

```yaml
Principle:
  name:
  description:
  why_it_matters:
  design_implications:
  failure_mode_if_ignored:
  measurable_signal:
```

Principles should be operational, not inspirational slogans.

---

## 4. Non-Goals and Anti-Patterns

Define what the system must not become.

Include:

```text
Do not become:
Avoid optimizing for:
Dangerous seductive shortcuts:
Prototype traps:
Business-model traps:
AI/model traps:
UX traps:
Operational traps:
Trust traps:
Safety traps:
Privacy traps:
```

Be adversarial and specific.

---

## 5. User Modes, Contexts, and Use Cases

Define the major modes in which the product will be used.

For each mode, use:

```yaml
Mode:
  name:
  user_intent:
  context:
  user_state:
  allowed_behaviors:
  disallowed_behaviors:
  success_feeling:
  risk_profile:
  required_system_capabilities:
  metrics:
```

Include:

```text
ordinary use cases
expert use cases
repeated-use cases
high-stakes cases
degraded cases
edge cases
misuse cases
first-time user case
power-user case
low-trust user case
```

---

## 6. Core System Capabilities

List the fundamental capabilities required for the mature version.

For each capability, use:

```yaml
Capability:
  name:
  description:
  user_value:
  required_inputs:
  required_outputs:
  dependencies:
  latency_or_timing_requirements:
  confidence_requirements:
  failure_behavior:
  difficult_to_add_later: true | false
  reason_it_is_core:
```

Explicitly identify which capabilities must be designed into the core from the beginning because adding them later would require major architectural rewrites.

---

## 7. Irreversible Architecture Decisions

Identify architecture choices that are difficult or expensive to change later.

Include:

```text
core primitives that must exist early
data abstractions that must not be skipped
policy engines that must not be encoded only in prompts
logging/replay systems that must exist from day one
privacy boundaries that must be architectural
provider abstractions that must be preserved
business-model constraints that must be encoded
trust mechanisms that must be designed early
```

For each, use:

```yaml
Decision:
  decision:
  why_it_matters:
  what_breaks_if_missing:
  minimum_viable_version:
  mature_version:
  migration_difficulty_if_ignored:
```

---

## 8. Data Model and Object Primitives

Define the core data objects.

Use YAML-style schemas.

Include domain-relevant objects such as:

```text
UserState
ContextState
DomainObject / WorldObject / WorkObject
Claim
Source
PolicyDecision
MemoryItem
FeedbackEvent
SessionTrace
SimulationScenario
ContentUnit
TaskUnit
RecommendationCandidate
ActionCandidate
RiskFlag
EvaluationResult
ProviderInterface
AuditRecord
```

Adapt object names to the project domain.

For each object, include:

```yaml
ObjectName:
  id:
  type:
  fields:
  relationships:
  confidence:
  validity:
  provenance:
  lifecycle:
  privacy_class:
  required_for:
```

Make schemas practical, detailed, and usable for downstream implementation.

---

## 9. Provenance, Truth, and Confidence Model

Define how the system knows what is true, uncertain, outdated, disputed, inferred, generated, user-provided, or high-risk.

Include:

```text
source-level provenance
claim-level provenance
confidence scoring
freshness scoring
contradiction detection
human verification
model-generated content restrictions
uncertainty language
suppression rules
auditability
source rights
licensing constraints
```

Use this schema and adapt it to the project:

```yaml
Claim:
  id:
  subject:
  predicate:
  value:
  source_ids:
  confidence:
  freshness:
  contradiction_status:
  verification_status:
  allowed_uses:
  prohibited_uses:
  privacy_class:
  user_visible_explanation:
```

Define a rule similar to:

```text
The model may compose, rank, summarize, or transform grounded information.
The model must not invent domain facts that affect user trust, safety, money, health, law, identity, reputation, or irreversible user decisions.
```

Adapt this rule to the project.

---

## 10. Temporal Model

Define how the system handles time.

Include:

```text
current truth
historical truth
future scheduled truth
seasonal truth
recurring truth
expiring truth
real-time state
stale data
prediction horizons
retention windows
validity periods
versioning
```

Use:

```yaml
TemporalValidity:
  valid_from:
  valid_until:
  recurrence:
  seasonality:
  historical_period:
  prediction_horizon:
  stale_after:
  refresh_required:
  expiration_behavior:
```

Explain what breaks if time is not a first-class dimension.

---

## 11. Personalization and Memory Model

Define what the system may remember, infer, forget, personalize, and expose.

Include memory classes:

```text
momentary state
session memory
short-term memory
long-term preference
explicit user setting
implicit behavior pattern
sensitive inference
history/log
training data candidate
user-owned archive
```

Use:

```yaml
MemoryItem:
  type:
  source:
  consent_required:
  retention:
  storage_location:
  user_visible:
  user_editable:
  deletion_behavior:
  personalization_allowed:
  sensitive:
```

Add rules:

```text
Use memory to reduce friction and improve relevance.
Do not use memory to manipulate, embarrass, expose, or over-personalize.
Do not reveal inferred personal patterns unless clearly useful, user-approved, and non-creepy.
Forgetting must be designed, not patched on later.
```

---

## 12. Privacy, Safety, and Trust Architecture

Define privacy and safety as system architecture, not compliance afterthoughts.

Include:

```text
sensitive data classes
data minimization
on-device vs cloud processing
retention limits
deletion semantics
user controls
audit logs
sensitive-context handling
high-stakes content restrictions
abuse cases
misuse prevention
trust explanations
consent boundaries
privacy-preserving defaults
```

Use:

```yaml
PrivacyClass:
  public:
  user_private:
  sensitive:
  regulated:
  ephemeral:
  forbidden:

SafetyPolicyDecision:
  allow:
  restrict:
  suppress:
  escalate:
  require_confirmation:
  reason:
  policy_source:
```

Include adversarial risks:

```text
creepiness
over-reliance
manipulation
surveillance incentives
unsafe automation
misinformation
commercial bias
social harm
security attacks
data leakage
coercive design
```

---

## 13. Attention, Cognitive Load, and Interruption Model

If the project interacts with user attention, define an explicit attention model.

Use:

```yaml
AttentionState:
  availability:
  cognitive_load:
  urgency:
  environment_complexity:
  social_context:
  competing_tasks:
  interruption_permission:
  suppression_reason:
```

Define when the product should:

```text
act
notify
speak
remain silent
defer
summarize later
ask confirmation
escalate
cancel
```

Even for non-audio products, define the equivalent of “silence.”

Core principle:

```text
Not acting is a valid output when action would reduce trust, safety, clarity, or user agency.
```

---

## 14. Policy Engines and Guardrails

Identify which decisions must be hard policy, not prompt instructions.

Include:

```text
safety policy
privacy policy
commercial influence policy
content quality policy
source rights policy
age/audience policy
sensitive context policy
high-stakes domain policy
abuse-prevention policy
accessibility policy
localization/cultural sensitivity policy
```

For each, use:

```yaml
Policy:
  name:
  applies_to:
  allowed:
  restricted:
  prohibited:
  escalation:
  logging_required:
  user_override_allowed:
  reason:
```

---

## 15. Content, Output, and Action Quality Bar

Define what excellent output looks like.

Depending on the project, this may include:

```text
text
audio
visuals
recommendations
actions
plans
alerts
automations
decisions
responses
diagnostics
summaries
```

For each output type, use:

```yaml
OutputType:
  purpose:
  required_quality:
  forbidden_patterns:
  required_grounding:
  freshness_requirement:
  personalization_allowed:
  confidence_language:
  ideal_length_or_density:
  cancellation_or_revision_rules:
```

Include examples of:

```text
good output
bad output
unacceptable output
```

---

## 16. Feedback, Correction, and User Control

Define user control primitives even if the system is intended to be automatic.

Include domain-appropriate versions of:

```text
pause
undo
mute
less
more
never show/say/do this
report wrong
report unsafe
report annoying
save
explain
edit preference
delete memory
export data
reset profile
```

Use:

```yaml
UserControlEvent:
  type:
  timestamp:
  target:
  scope:
  effect:
  reversibility:
  privacy_implication:
```

Feedback schema:

```yaml
FeedbackEvent:
  target_id:
  category:
  severity:
  free_text:
  context_snapshot:
  correction:
  downstream_effect:
```

---

## 17. Replay, Simulation, and Testing Infrastructure

Define how the system can be debugged, evaluated, reproduced, and improved.

Include:

```text
session replay
decision logs
model input/output logs
policy decision logs
suppression logs
simulation engine
synthetic scenarios
golden test cases
benchmark routes/workflows/tasks
regression tests
red-team tests
privacy-safe traces
counterfactual testing
```

Use:

```yaml
SessionTrace:
  id:
  timeline:
  input_events:
  state_snapshots:
  candidate_generation:
  ranking_decisions:
  policy_decisions:
  output_events:
  user_feedback:
  errors:
  privacy_redactions:

SimulationScenario:
  id:
  scenario_type:
  initial_state:
  event_sequence:
  noise_model:
  expected_behavior:
  forbidden_behavior:
  evaluation_metrics:
```

Explain why replay and simulation must exist early.

---

## 18. Evaluation Metrics and Anti-Metrics

Define success metrics, quality metrics, safety metrics, trust metrics, economic metrics, and anti-metrics.

Include:

```text
Primary product metrics
Secondary diagnostics
Safety metrics
Trust metrics
Privacy metrics
Operational metrics
Economic metrics
Long-term retention metrics
Failure metrics
Anti-metrics that must not be optimized
```

For each metric, use:

```yaml
Metric:
  name:
  definition:
  target:
  measurement_method:
  failure_threshold:
  gaming_risk:
```

Include at least 25 metrics.

---

## 19. Failure Modes and Adversarial Postmortem

Pretend the project failed after launch.

Write a brutally honest postmortem.

Include failures caused by:

```text
wrong product thesis
bad timing
bad UX rhythm
trust loss
technical latency
data quality
model hallucination
privacy concerns
safety incidents
cost structure
platform dependency
commercial incentives
low retention
novelty decay
poor onboarding
edge cases
lack of ordinary-use value
operational bottlenecks
```

Map each failure to architectural prevention.

Use:

```yaml
FailureMode:
  description:
  root_cause:
  early_warning_signal:
  prevention:
  detection:
  recovery:
  severity:
```

---

## 20. MVP vs Mature System

Separate what must be built first from what must merely be architected for.

Use a table:

```text
Capability | Must Build in MVP | Must Architect for MVP | Can Defer | Dangerous to Defer | Notes
```

Identify:

```text
prototype-only shortcuts
MVP-acceptable compromises
MVP-forbidden compromises
mature-system requirements
capabilities that are not user-visible but must exist early
```

---

## 21. Roadmap by System Layer

Provide a staged roadmap.

Use phases:

```text
Phase 0: Research and validation
Phase 1: Instrumented prototype
Phase 2: Controlled pilot
Phase 3: Trusted MVP
Phase 4: Scalable product
Phase 5: Platform/ecosystem
```

For each phase, use:

```yaml
Phase:
  goals:
  build:
  do_not_build_yet:
  success_criteria:
  kill_criteria:
  major_risks:
  required_metrics:
```

---

## 22. Operational Requirements

Define the non-user-facing systems required to operate quality.

Include:

```text
content operations
moderation tools
quality review
source management
cost monitoring
abuse monitoring
incident response
model evaluation
provider failover
data retention enforcement
privacy review
human escalation
localization review
accessibility review
customer support workflows
```

For each, use:

```yaml
OperationalSystem:
  name:
  purpose:
  users:
  required_tools:
  data_needed:
  risks_if_missing:
```

---

## 23. Provider and Dependency Abstractions

Avoid locking the project to a single model, API, hardware provider, payment provider, map provider, data provider, or platform.

Use:

```yaml
ProviderInterface:
  domain:
  provider:
  capabilities:
  cost_model:
  latency:
  reliability:
  rights:
  geographic_or_market_coverage:
  fallback:
  replacement_difficulty:
```

Define where abstraction is mandatory and where provider-specific optimization is acceptable.

---

## 24. Commercial and Incentive Design

Define the business model constraints required to preserve trust.

Include:

```text
what can be monetized
what must never be monetized
whether ads are allowed
whether sponsored ranking is allowed
whether data sale is allowed
whether paid recommendations are allowed
required disclosures
conflicts of interest
user trust boundaries
commercial influence logging
```

Use:

```yaml
CommercialPolicy:
  allowed_revenue:
  prohibited_revenue:
  disclosure_required:
  ranking_influence_allowed:
  user_control_required:
  trust_risk:
```

---

## 25. Accessibility, Inclusion, and Cultural Adaptation

Define accessibility and localization from the beginning.

Include:

```text
language support
cultural adaptation
disability access
age sensitivity
literacy variation
economic access
regional norms
sensitive historical/political contexts
pronunciation/naming
units/formats
cognitive-load differences
```

Use:

```yaml
AudienceProfile:
  language:
  region:
  age_class:
  accessibility_needs:
  cognitive_load_preference:
  cultural_sensitivity:
  output_format_preferences:
```

---

## 26. Security and Abuse Resistance

Define attack surfaces.

Include:

```text
prompt injection
data poisoning
fake sources
malicious third-party content
account takeover
stalking risks
location abuse
model manipulation
commercial manipulation
policy bypass
unsafe automation
private-data leakage
social engineering
```

For each, use:

```yaml
Threat:
  name:
  attack_path:
  impact:
  likelihood:
  prevention:
  detection:
  response:
  residual_risk:
```

---

## 27. Golden Standard Examples

Provide 10-20 examples of ideal behavior.

For each, use:

```yaml
Example:
  scenario:
  user_context:
  system_state:
  output_or_action:
  why_it_is_good:
  what_not_to_do:
  metrics_impacted:
```

Also provide 10-20 examples of bad behavior and why they fail.

---

## 28. Final North Star Bar

End with a concise but dense definition of what the project must become.

Include:

```text
The product becomes revolutionary when:
The product remains mediocre if:
The hardest thing to get right is:
The most dangerous shortcut is:
The most important architectural primitive is:
The most important user trust promise is:
The ultimate rule is:
```

---

# Style Requirements

- Be direct, specific, and implementation-aware.
- Avoid fluffy adjectives unless tied to concrete behavior.
- Prefer structured schemas and explicit rules.
- Include failure conditions, confidence thresholds, suppression rules, and evaluation criteria.
- State assumptions clearly.
- When uncertain, define how the system should behave under uncertainty.
- Use domain-specific reasoning, not generic startup advice.
- Include both user-facing and non-user-facing infrastructure.
- Include things that must be designed early even if not built in MVP.
- Treat privacy, safety, trust, replayability, and evaluation as core architecture.
- Do not over-index on the first prototype.
- Assume downstream systems may trim this document, so include redundant but useful detail.
- Produce the final answer as a complete Markdown spec, not a conversation.
```

---

# Short Version

Use this version when you need a faster prompt.

```markdown
Create a detail-rich North Star Specification for [PROJECT NAME].

Act as a senior product architect, systems designer, technical strategist, adversarial reviewer, privacy/safety architect, and implementation planner.

The document will be processed by future LLMs, so make it highly structured, dense, explicit, and trim-friendly. Use Markdown, tables, YAML-style schemas, metrics, decision rules, failure modes, object models, policy models, and evaluation criteria.

Do not write a pitch. Do not write vague strategy. Define what the project must become to be truly excellent, scalable, trustworthy, and hard to copy.

Project description:
[INSERT PROJECT DESCRIPTION]

Target users:
[INSERT USERS]

Desired experience:
[INSERT EXPERIENCE]

Constraints:
[INSERT CONSTRAINTS]

Known risks:
[INSERT RISKS]

Explicit non-goals:
[INSERT NON-GOALS]

Produce sections covering:

1. Executive definition
2. North Star thesis
3. Core experience principles
4. Non-goals and anti-patterns
5. User modes and contexts
6. Core system capabilities
7. Irreversible architecture decisions
8. Core data models and object primitives
9. Provenance, truth, and confidence model
10. Temporal validity model
11. Personalization and memory model
12. Privacy, safety, and trust architecture
13. Attention/interruption/suppression model
14. Policy engines and guardrails
15. Output/action quality bar
16. Feedback, correction, and user controls
17. Replay, simulation, and testing infrastructure
18. Evaluation metrics and anti-metrics
19. Failure modes and adversarial postmortem
20. MVP vs mature system distinction
21. Roadmap by system layer
22. Operational requirements
23. Provider/dependency abstractions
24. Commercial and incentive design
25. Accessibility, inclusion, and cultural adaptation
26. Security and abuse resistance
27. Golden standard examples and bad examples
28. Final North Star bar

For every major capability, specify:

```yaml
Capability:
  name:
  description:
  user_value:
  required_inputs:
  required_outputs:
  dependencies:
  confidence_requirements:
  latency_or_timing_requirements:
  failure_behavior:
  difficult_to_add_later: true | false
  reason_it_is_core:
```

For every major data object, specify:

```yaml
Object:
  id:
  type:
  fields:
  relationships:
  provenance:
  confidence:
  temporal_validity:
  privacy_class:
  lifecycle:
  required_for:
```

Pretend the product failed after launch. Identify root causes and design the architecture to prevent them.

Assume ambitious long-term capabilities, but stay realistic about human behavior, regulation, trust, economics, operational complexity, latency, safety, and data quality.

Final rule: produce a complete Markdown North Star spec, dense enough to become the foundation for product requirements, technical architecture, MVP planning, evaluation, and implementation.
```

---

# Optional Add-On: Make the Output More Technical

Append this to the prompt when the output should be closer to a system-design document.

```markdown
Increase technical depth.

For each major system, include:

```yaml
SystemComponent:
  purpose:
  responsibilities:
  inputs:
  outputs:
  internal_state:
  APIs:
  storage:
  latency_budget:
  failure_modes:
  observability:
  security_controls:
  privacy_controls:
  MVP_version:
  mature_version:
```

Also include:

- service boundaries
- event flows
- data lifecycle
- data retention rules
- provider abstraction interfaces
- fallback paths
- cache strategy
- cost model
- monitoring and alerting
- simulation and replay architecture
- red-team scenarios
- technical debt traps
```

---

# Optional Add-On: Make the Output More Product-Oriented

Append this when the output should be closer to a product strategy and requirements document.

```markdown
Increase product depth.

For each user mode and feature, include:

```yaml
ProductRequirement:
  user_story:
  user_value:
  acceptance_criteria:
  non_goals:
  edge_cases:
  privacy_considerations:
  safety_considerations:
  success_metrics:
  failure_metrics:
  MVP_scope:
  mature_scope:
```

Also include:

- onboarding requirements
- user controls
- feedback flows
- trust-building moments
- retention loops
- ordinary-use value
- novelty decay prevention
- pricing implications
- support implications
- launch sequencing
```

---

# Optional Add-On: Make the Output More Adversarial

Append this when you want the model to be harsher.

```markdown
Be more adversarial.

Pretend the product failed badly after launch. Identify the deepest reasons why.

For each failure, include:

```yaml
AdversarialFailure:
  failure:
  why_it_was_predictable:
  ignored_warning_signs:
  architectural_root_cause:
  product_root_cause:
  trust_or_safety_damage:
  prevention:
  detection_metric:
  kill_or_pivot_threshold:
```

Challenge the core thesis. Identify where the product may be a demo rather than a durable habit. Identify what would make users abandon it after novelty fades. Identify what must be true for repeat use.
```
