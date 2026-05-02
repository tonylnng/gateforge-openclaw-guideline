# GateForge Project File — `<project_name>`

> **Class C — Project-specific.** This file lives in the project's Blueprint repo at `project/gateforge_<project_name>.md` and is the **only** place project-specific decisions, overrides, and notes belong.
>
> **Do NOT** copy this file into `gateforge-openclaw-guideline` or any variant directory. **Do NOT** edit the Class A or Class B files (`SOUL.md`, `AGENTS.md`, `USER.md`, `TOOLS.md`, the role guides) to encode project content — every project edit there breaks future guideline upgrades.
>
> See [`CONTRIBUTING.md` § Class A/B/C](https://github.com/tonylnng/gateforge-openclaw-guideline/blob/main/CONTRIBUTING.md#file-authorship-rules--class-a--b--c) in the guideline repo.

---

## Metadata

| Field | Value |
|-------|-------|
| **Project name** | `<project_name>` |
| **Created** | `<YYYY-MM-DD>` |
| **Operator** | `<name>` |
| **Variant** | `multi-agent` \| `single-agent` |
| **Guideline repo** | `tonylnng/gateforge-openclaw-guideline` |
| **Guideline version** | `<vMAJOR.MINOR.PATCH>` |
| **Guideline commit (pinned)** | `<40-char SHA>` |
| **Blueprint repo** | `tonylnng/<project_name>-blueprint` |
| **Code repo** | `tonylnng/<project_name>-code` |

---

## 1. Project Glossary

Domain-specific terms used in this project. Add entries that the methodology guides do not already define.

| Term | Definition |
|------|------------|
| `<term>` | `<definition>` |

---

## 2. Stack Deviations

Document every place this project deviates from the default GateForge stack (TypeScript / NestJS / React / Docker / Redis / PostgreSQL / Kubernetes). Each deviation MUST have a justification.

| Component | Default | This project | Justification | Approved by | Date |
|-----------|---------|--------------|---------------|-------------|------|
| `<area>` | `<default>` | `<deviation>` | `<why>` | `<operator>` | `<YYYY-MM-DD>` |

If the cell list is empty, the project follows the default stack.

---

## 3. Compliance Overrides

Methodology controls that are **stricter** than the OWASP / ISO 25010 / SRE baseline because of regulatory or contractual obligations.

| Regime | Control | Stricter requirement | Source (regulation, contract clause) |
|--------|---------|----------------------|--------------------------------------|
| `<HIPAA \| GDPR \| PCI-DSS \| SOC2 \| ...>` | `<control>` | `<requirement>` | `<source>` |

If empty, the project uses the methodology baseline as-is.

---

## 4. Custom Quality Gates

Extra checklist items the project enforces **on top of** the standard phase-exit checklists in the role guides.

### PM exit (project-additional)

- [ ] `<additional check>`

### DESIGN exit (project-additional)

- [ ] `<additional check>`

### DEV exit (project-additional)

- [ ] `<additional check>`

### QA exit (project-additional)

- [ ] `<additional check>`

### QC exit (project-additional)

- [ ] `<additional check>`

### OPS exit (project-additional)

- [ ] `<additional check>`

---

## 5. Project-Specific Decisions

Decisions that are too narrow to be ADRs (those go in `project/decisions/`) but too durable to be commit messages.

| ID | Date | Decision | Rationale | Affected phases |
|----|------|----------|-----------|-----------------|
| `PD-001` | `<date>` | `<decision>` | `<why>` | `<phases>` |

---

## 6. Known Exceptions

One-off exceptions the operator has explicitly approved. Each exception MUST have an end-date or a re-evaluation trigger.

| ID | Description | Approved by | Date approved | Expires / re-evaluate when |
|----|-------------|-------------|---------------|----------------------------|
| `EX-001` | `<exception>` | `<operator>` | `<date>` | `<trigger>` |

---

## 7. Notes for the Agent

Free-form prose the operator wants the agent to keep in mind. Updated by the operator only. Examples:

- Style preferences (e.g. "use British English in user-facing copy").
- Stakeholders to copy on Telegram approvals.
- Time-zones for daily status reports.
- Vendor or integration quirks the methodology cannot anticipate.

```
<your notes here>
```

---

## 8. Revision History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 0.1.0 | `<date>` | `<operator>` | Initial scaffold from `gateforge_PROJECT_TEMPLATE.md` |
