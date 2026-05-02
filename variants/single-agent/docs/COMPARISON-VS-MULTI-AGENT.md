# Comparison — Single Agentic SDLC vs Multi-Agent SDLC

The two GateForge SDLC variants share the same **discipline** (Blueprint, IEEE / ISO / OWASP / ISTQB / SRE / ITIL standards, Telegram-gated approvals, conventional commits with phase prefix) but diverge sharply on **execution topology**.

## Side-by-side

| Dimension                       | Multi-Agent (`gateforge-openclaw-configs`)                               | Single-Agent (`gateforge-openclaw-single`)                          |
|---------------------------------|--------------------------------------------------------------------------|---------------------------------------------------------------------|
| Number of OpenClaw agents       | 5 (architect, designer, developers, QC, operator)                        | 1                                                                   |
| Number of VMs                   | 5                                                                        | 1                                                                   |
| Models                          | Per-role (e.g. Sonnet for design, Haiku for QC, larger for dev)          | One model for all phases (default `anthropic/claude-sonnet-4-6`)    |
| Phase transitions               | HMAC-signed HTTP notifications via gateway hub                           | State changes in `project/state.md` + commit trailers               |
| Tokens                          | `OPENCLAW_TOKEN` per VM + 4 gateway tokens + HMAC secret                 | One `OPENCLAW_TOKEN` plus app tokens (Anthropic, Telegram, GitHub)  |
| Sandbox mode                    | Per-role (e.g. `read-only` for architect, `all` for dev/QC)              | `all` because the same agent does code exec and test exec           |
| Peer review                     | One agent reviews another's output                                       | Self-review: agent re-loads role guide and re-reads its own output  |
| Hand-off cost                   | Network call + HMAC verification + queue wait                            | File commit + role-guide reload                                     |
| Failure-mode blast radius       | Bounded by VM (a buggy dev cannot corrupt the architect's filesystem)    | Whole project at risk — discipline + Docker sandbox are the seatbelt|
| Concurrency                     | True parallel (e.g. designer can review while developer codes elsewhere) | Serial within a project; agent can fan out to multiple projects     |
| Cost (typical small project)    | Higher (5 VMs running, multiple model subscriptions)                     | Lower (1 VM, 1 subscription)                                        |
| Latency for full SDLC pass      | Higher hand-off overhead, but parallel work compensates on big projects  | Lower for small projects; grows linearly with project size          |
| Onboarding complexity           | High — install 5 VMs, exchange 9 secrets                                 | Low — one VM, one install script                                    |

## When to choose which

Pick the **multi-agent** variant when:

- Project is large enough that phases run in parallel (e.g. design of feature B while dev of feature A continues).
- Compliance regime requires segregation of duties (designer cannot also be developer).
- Per-role model specialisation is worth the operational overhead.
- Multiple humans collaborate and want to talk to different agents per role.

Pick the **single-agent** variant when:

- Project is small (think: a CLI tool, an internal microservice, a static site, a one-off data pipeline).
- One human user is the only stakeholder.
- Operational simplicity matters more than parallelism.
- The agent's monthly bill must stay flat.

## Discipline preserved across both variants

The following are **identical** in both repos and must remain so:

- Blueprint structure (`gateforge-blueprint-template`).
- Filename compliance rules in `SOUL.md`.
- Conventional commits with phase prefix `[PM]/[Design]/[Dev]/[QA]/[QC]/[Ops]`.
- Quality gates (IEEE 830, ISO 25010, C4, OWASP ASVS, IEEE 829, ISTQB, SRE, ITIL, SemVer).
- Telegram-gated `Approved` for production deploys.
- ADR format and `project/decisions/` location.
- Standard Definition of Done.

## Discipline that **moves** between variants

| Discipline                             | Multi-Agent enforcement       | Single-Agent enforcement                          |
|----------------------------------------|-------------------------------|---------------------------------------------------|
| Cross-role review                      | Network hand-off              | Role-guide reload + self-review checklist         |
| "No designer touches code"             | Sandbox mode `read-only`      | Phase-machine state guard + commit trailer audit  |
| Token leakage prevention               | Per-VM tokens                 | Single token + scoped commit trailers + `umask 077`|
| Tamper-evidence                        | HMAC notification chain       | Git history + GateForge commit trailers           |
