# QA Framework — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For variant-specific runtime deltas, read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)

> **Status:** Active

---

## 1. Framework Overview

### 1.1 Purpose and Scope

This document defines the complete Quality Assurance framework for the GateForge multi-agent SDLC pipeline. It is the authoritative reference for all QC agents running on VM-4. Every testing decision, report format, and quality gate threshold is codified here.

**What this framework covers:**
- How to test code produced by Developer agents (VM-3)
- How to evaluate compliance against Blueprint specifications from System Designer (VM-2)
- How to produce structured, machine-parseable QA reports
- How to enforce quality gates that govern the PROMOTE / HOLD / ROLLBACK decision
- How to integrate with the Lobster pipeline's deterministic orchestration

**What this framework does NOT cover:**
- Infrastructure provisioning (VM-5 Operator responsibility)
- Architecture decisions (VM-1 Architect responsibility)
- Code fixes (VM-3 Developer responsibility — QC agents are read-only on code)

### 1.2 How This Framework Fits in the GateForge SDLC Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GateForge SDLC Pipeline                          │
│                                                                     │
│  VM-1 Architect ──blueprint──▶ VM-2 Designer ──spec──▶ VM-3 Devs   │
│       (Opus 4.6)                (Sonnet 4.6)          (Sonnet 4.6)  │
│                                                           │         │
│                                                      code push      │
│                                                           │         │
│                                                           ▼         │
│                                                  ┌───────────────┐  │
│                                                  │   VM-4 QC     │  │
│                                                  │  (MiniMax 2.7)│  │
│                                                  │               │  │
│                                                  │  git pull     │  │
│                                                  │  run tests    │  │
│                                                  │  produce JSON │  │
│                                                  │  gate verdict │  │
│                                                  └───────┬───────┘  │
│                                                          │          │
│                                    ┌─────────────────────┤          │
│                                    │                     │          │
│                               PROMOTE              HOLD/ROLLBACK   │
│                                    │                     │          │
│                                    ▼                     ▼          │
│                              VM-5 Operator       Back to VM-3 Devs │
│                              (deploy)            (fix + re-submit)  │
│                                                  (max 3 loops)      │
└─────────────────────────────────────────────────────────────────────┘
```

The QC agent sits at the critical gate between development and deployment. No code reaches VM-5 without passing through this framework.

### 1.3 QC Agent Responsibilities vs Other Agents

| Agent | VM | Responsibilities | Interaction with QC |
|-------|-----|-----------------|---------------------|
| System Architect | VM-1 | Pipeline orchestration, task decomposition, Lobster configs | Sends test tasks to QC; receives gate verdicts |
| System Designer | VM-2 | Blueprint specs, API contracts, data schemas | QC validates code against Designer's specs |
| Developers | VM-3 | Code implementation, unit test authoring | QC runs their tests, writes additional tests, reports defects |
| **QC Agents** | **VM-4** | **Test execution, quality gating, defect reporting** | **This document** |
| Operator | VM-5 | CI/CD, deployment, monitoring | Receives PROMOTE signal from QC |

### 1.4 QC Agent Available Tools

| Tool | Purpose in QA Workflow |
|------|----------------------|
| `exec` (sandboxed) | Run test suites, linters, static analysis, coverage tools |
| `read` | Inspect source code, config files, specs |
| `write` | Generate test files, reports, golden dataset entries |
| `edit` | Modify test configurations (never production code) |
| `web_fetch` | Retrieve dependency docs, API specs, CVE databases |
| `git` | Pull latest code, check diffs, read commit history |

**Critical constraint:** QC agents can `git pull` but **cannot `git push`**. Code fixes are the Developer's responsibility. QC agents produce defect reports that describe what to fix, not patches.

---

## 2. Testing Principles for AI Agents

### 2.1 Why AI Agent Testing Differs from Traditional QA

Traditional software testing assumes deterministic behavior: the same input always produces the same output. AI agent pipelines break this assumption in two ways:

1. **Non-deterministic LLM outputs:** Even with temperature=0, model outputs can vary across versions, context windows, and hardware.
2. **Emergent multi-agent behavior:** Five agents interacting can produce behaviors none was individually designed for.

The GateForge pipeline mitigates non-determinism through the Lobster orchestration layer, which enforces deterministic *routing* and *gating* even when individual agent outputs are stochastic. This framework leverages that architectural decision.

> **Reference:** The distinction between testing traditional vs. LLM applications is well-established in the literature. Non-deterministic outputs and evolving model behavior make traditional testing insufficient for release governance ([arXiv:2603.15676](https://arxiv.org/abs/2603.15676)).

### 2.2 Deterministic vs Non-Deterministic Testing

| Aspect | Deterministic Tests | Non-Deterministic Tests |
|--------|-------------------|------------------------|
| Output expectation | Exact match | Semantic equivalence / rubric scoring |
| Repeatability | 100% reproducible | Statistical (run N times, measure pass rate) |
| Examples | Unit tests, schema validation, lint | Code review quality, spec compliance |
| Verdict | Binary PASS/FAIL | Scored (1-5) with threshold |
| Use in gates | Hard gates (must pass) | Soft gates (aggregate score ≥ threshold) |

**Rule:** Always prefer deterministic tests. Use non-deterministic evaluation (LLM-as-Judge) only when the property being tested cannot be reduced to a deterministic check.

### 2.3 Structured Output as First-Class Requirement

Every QC agent output must be structured JSON. Free-text reports are prohibited for machine-consumed outputs. This enables:
- Automated gate decisions by the Lobster pipeline
- Aggregation and trending across builds
- Unambiguous communication between agents

**Principle:** If it cannot be parsed by `JSON.parse()`, it does not exist as a QA artifact.

### 2.4 The "LLM Does Creative Work, Framework Does Routing/Gating" Principle

```
┌──────────────────────────────────────────────────────────┐
│                    Separation of Concerns                 │
│                                                          │
│  LLM (MiniMax 2.7):                                     │
│    ✓ Analyze code for logic errors                       │
│    ✓ Generate test cases from specs                      │
│    ✓ Evaluate code quality against rubrics               │
│    ✓ Produce natural-language defect descriptions         │
│                                                          │
│  Framework (Lobster + this QA Framework):                │
│    ✓ Route tasks to appropriate test levels               │
│    ✓ Enforce threshold arithmetic (≥95% → PASS)          │
│    ✓ Decide PROMOTE / HOLD / ROLLBACK                    │
│    ✓ Manage iteration counters (max 3 loops)             │
│    ✓ Aggregate scores into gate verdicts                 │
└──────────────────────────────────────────────────────────┘
```

The LLM never decides whether to promote a build. The LLM produces scores and observations. The framework applies deterministic logic to those scores.

> **Reference:** Effective evaluation platforms separate qualitative LLM assessment from deterministic decision-making, combining programmatic, statistical, and LLM-as-a-judge evaluators at multiple levels ([Maxim AI](https://www.getmaxim.ai/articles/how-to-evaluate-your-ai-agents-effectively/)).

---

## 3. Multi-Level Test Architecture

The test architecture follows a multi-level evaluation approach, adapted from industry best practices for AI agent systems.

> **Reference:** Multi-level evaluation (component, integration, end-to-end) is the standard architecture for AI agent testing ([Maxim AI](https://www.getmaxim.ai/articles/how-to-evaluate-your-ai-agents-effectively/)).

### 3.1 Level 1 — Component Testing (Unit)

**Why:** Catch defects at the smallest possible scope. Unit tests are deterministic, fast, and cheap to run.

**What is tested:**
- Individual functions and methods
- Pure logic (no external dependencies)
- Data transformations
- Utility and helper functions
- Error handling paths

**How the QC agent executes Level 1:**

1. `git pull` the latest code from the development branch
2. Identify the test runner (detect from `package.json`, `pyproject.toml`, `Makefile`, or Lobster task config)
3. Execute the test suite:
   ```bash
   # Example for Python
   exec: pytest tests/unit/ --json-report --json-report-file=unit-results.json --cov=src/ --cov-report=json
   
   # Example for Node.js
   exec: npx jest tests/unit/ --json --outputFile=unit-results.json --coverage --coverageReporters=json
   ```
4. Parse results into the standard report format (Section 11.1)
5. Compute pass rate: `passed / (passed + failed + error)`
6. Compute line coverage for P0 modules

**Gate criteria:**
| Metric | Threshold | Critical Failure |
|--------|-----------|-----------------|
| Unit test pass rate | ≥ 95% | < 66.5% (70% of 95%) |
| Line coverage (P0 modules) | ≥ 80% | < 56% (70% of 80%) |
| Line coverage (P1 modules) | ≥ 60% | < 42% (70% of 60%) |

### 3.2 Level 2 — Integration Testing

**Why:** Units that pass individually may fail when composed. Integration tests verify that modules communicate correctly and data formats match across boundaries.

**What is tested:**
- API endpoint request/response contracts
- Database query integration
- Inter-service communication
- Message queue producers/consumers
- External dependency mocking and contract validation

**How the QC agent executes Level 2:**

1. Validate API contracts against OpenAPI/Swagger specs:
   ```bash
   exec: npx @stoplight/spectral-cli lint openapi.yaml --format json > api-lint.json
   ```
2. Run integration test suite:
   ```bash
   exec: pytest tests/integration/ --json-report --json-report-file=integration-results.json
   ```
3. Validate data schema compliance (JSON Schema, protobuf):
   ```bash
   exec: ajv validate -s schemas/ -d test-fixtures/ --all-errors --json > schema-validation.json
   ```
4. Parse and aggregate results

**Gate criteria:**
| Metric | Threshold | Critical Failure |
|--------|-----------|-----------------|
| Integration test pass rate | ≥ 90% | < 63% |
| API contract compliance | 100% | < 70% |
| Schema validation | 100% | < 70% |

### 3.3 Level 3 — End-to-End Testing

**Why:** Full user journeys may expose emergent issues that neither unit nor integration tests catch. E2E tests simulate real workflows through the complete system.

> **Reference:** End-to-end tests for agentic systems rely on golden datasets containing representative examples with known correct outputs, functioning as regression benchmarks ([ML Architects Basel](https://ml-architects.ch/blog_posts/testing_qa_ai_eingineering.html)).

**What is tested:**
- Complete user workflows (create → read → update → delete)
- Multi-step agent interaction chains
- Error recovery paths
- Data consistency across the full pipeline

**How the QC agent executes Level 3:**

1. Load E2E test scenarios from the golden dataset (Section 4)
2. Execute scenarios against the running system:
   ```bash
   exec: pytest tests/e2e/ --json-report --json-report-file=e2e-results.json
   ```
3. Compare actual outputs against golden dataset expected outputs
4. Apply semantic comparison where exact match is not feasible (use LLM-as-Judge for text outputs)

**Gate criteria:**
| Metric | Threshold | Critical Failure |
|--------|-----------|-----------------|
| E2E scenario pass rate | ≥ 85% | < 59.5% |
| Critical path pass rate | 100% | < 70% |

### 3.4 Level 4 — Performance & Load Testing

**Why:** Code that is functionally correct may be unacceptably slow under load. Performance regressions must be caught before deployment.

**What is tested:**
- Response time under normal load
- Response time under peak load (2x normal)
- Memory consumption and leak detection
- CPU utilization trends
- Throughput (requests/second)

**How the QC agent executes Level 4:**

1. Run benchmark suite:
   ```bash
   exec: k6 run tests/performance/load-test.js --out json=perf-results.json
   ```
2. Collect P50, P95, P99 latency values
3. Compare against baseline from previous PROMOTED build
4. Check for memory leaks (growth > 10% over sustained load)

**Gate criteria:**
| Metric | Threshold | Critical Failure |
|--------|-----------|-----------------|
| P95 latency | ≤ spec value (per endpoint) | > 200% of spec |
| P99 latency | ≤ 2x spec value | > 300% of spec |
| Memory growth (10-min sustained) | ≤ 10% | > 50% |
| Error rate under load | ≤ 1% | > 5% |

> **Reference:** P95 latency is one of five empirically grounded quality dimensions for AI system release governance ([arXiv:2603.15676](https://arxiv.org/abs/2603.15676)).

### 3.5 Level 5 — Security Testing

**Why:** Security vulnerabilities in production can have catastrophic consequences. Automated security scanning catches known vulnerability patterns before deployment.

**What is tested:**
- Dependency vulnerabilities (CVE database)
- Static Application Security Testing (SAST)
- Secret/credential detection in codebase
- Input validation and injection resistance
- Authentication/authorization correctness

**How the QC agent executes Level 5:**

1. Dependency audit:
   ```bash
   exec: npm audit --json > dep-audit.json
   # or
   exec: pip-audit --format=json > dep-audit.json
   ```
2. SAST scanning:
   ```bash
   exec: semgrep --config=auto --json > sast-results.json
   ```
3. Secret scanning:
   ```bash
   exec: gitleaks detect --report-format=json --report-path=secrets-report.json
   ```
4. Aggregate findings by severity

**Gate criteria:**
| Metric | Threshold | Critical Failure |
|--------|-----------|-----------------|
| Critical vulnerabilities | 0 | ≥ 1 |
| High vulnerabilities | 0 | ≥ 3 |
| Medium vulnerabilities | ≤ 5 | > 20 |
| Exposed secrets | 0 | ≥ 1 |

---

## 4. Golden Dataset Management

### 4.1 Why Golden Datasets

A golden dataset is the QC agent's source of truth — a curated collection of inputs paired with verified outputs that define expected system behavior. It serves as both a regression test suite and a quality benchmark.

> **Reference:** A golden dataset is a curated, versioned collection of prompts, inputs, contexts, and expected outcomes that becomes the source of truth for measuring quality across the AI lifecycle. Aim for 50 to 500 diverse high-quality entries ([Maxim AI — Building a Golden Dataset](https://www.getmaxim.ai/articles/building-a-golden-dataset-for-ai-evaluation-a-step-by-step-guide/); [ML Architects Basel](https://ml-architects.ch/blog_posts/testing_qa_ai_eingineering.html)).

### 4.2 Golden Dataset Entry Schema

Every entry in the golden dataset follows this schema:

```json
{
  "id": "GD-0001",
  "tier": "core_functional",
  "category": "api_endpoint",
  "component": "user-service",
  "priority": "P0",
  "created": "2026-04-07T00:00:00Z",
  "last_validated": "2026-04-07T00:00:00Z",
  "input": {
    "type": "http_request",
    "method": "POST",
    "path": "/api/v1/users",
    "headers": { "Content-Type": "application/json" },
    "body": { "name": "Test User", "email": "test@example.com" }
  },
  "expected_output": {
    "status_code": 201,
    "body_schema": "schemas/user-response.json",
    "body_contains": { "name": "Test User" },
    "latency_max_ms": 500
  },
  "context": {
    "blueprint_ref": "BP-USR-001",
    "acceptance_criteria": "AC-USR-001-03",
    "related_entries": ["GD-0002", "GD-0015"]
  },
  "validation_method": "deterministic",
  "tags": ["user-management", "create", "happy-path"]
}
```

### 4.3 Stratification Tiers

The golden dataset is stratified into four tiers to ensure comprehensive coverage and prevent overfitting to easy cases.

> **Reference:** The automated self-testing framework uses a stratified question bank with four tiers as an anti-overfitting mechanism, ensuring test suites exercise diverse failure modes ([arXiv:2603.15676](https://arxiv.org/abs/2603.15676)).

| Tier | Description | Target % of Dataset | Examples |
|------|-------------|-------------------|----------|
| **Core Functional** | Happy-path scenarios for all major features | 40% | CRUD operations, auth flows, data queries |
| **Complex Orchestration** | Multi-step workflows, cross-service interactions | 25% | Order → payment → notification chains |
| **Edge Cases / Hallucination Traps** | Boundary values, malformed inputs, prompts designed to trigger incorrect behavior | 20% | Empty strings, max-length inputs, SQL in text fields, misleading context |
| **Adversarial / Safety** | Intentional attacks, privilege escalation, injection attempts | 15% | XSS payloads, CSRF tokens, auth bypass attempts |

### 4.4 Maintenance Cadence

| Trigger | Action |
|---------|--------|
| New feature added | Add ≥ 3 entries per tier for the feature |
| Escaped defect (bug found in production) | Add golden entry that would have caught it |
| Model upgrade (any VM) | Re-validate all entries; update expected outputs where behavior legitimately changed |
| Weekly cadence | Review entries flagged as flaky (pass rate < 100% over last 5 runs) |
| Dataset size < 50 | Prioritize expansion; block PROMOTE until minimum reached |
| Dataset size > 500 | Audit for redundancy; archive low-value entries |

### 4.5 Anti-Overfitting Practices

1. **Stratification enforcement:** Every test run must sample proportionally from all four tiers. Running only Tier 1 is prohibited.
2. **Rotation:** 10% of entries are randomly excluded from each run and replaced with newly generated entries.
3. **Blind entries:** Developers never see the full golden dataset. They receive only the test case IDs and pass/fail status.
4. **Periodic refresh:** Monthly, generate 10-20 new entries using the Test Case Generation Protocol (Section 5) and retire the 10-20 lowest-value existing entries.

---

## 5. Test Case Generation Protocol

### 5.1 Input Requirements

Test case generation requires these inputs:

| Input | Source | Required? |
|-------|--------|-----------|
| Blueprint specification | VM-2 System Designer | Yes |
| Acceptance criteria | Blueprint spec | Yes |
| API contracts (OpenAPI/Swagger) | VM-2 System Designer | If applicable |
| Data schemas (JSON Schema, protobuf) | VM-2 System Designer | If applicable |
| Code diff (current PR/change) | VM-3 Developers (via git) | Yes |
| Previous test results | QC agent local storage | If available |
| Defect history | QC agent defect database | If available |

> **Reference:** NVIDIA's HEPH framework demonstrates that structured input parsing (specs → test cases), iterative generation with coverage tracking, and feedback loops from execution results are best practices for AI-driven test generation ([NVIDIA Technical Blog — HEPH](https://developer.nvidia.com/blog/building-ai-agents-to-automate-software-test-case-creation/)).

### 5.2 Test Case Schema

Every generated test case follows this schema:

```json
{
  "test_id": "TC-USR-001-03",
  "blueprint_ref": "BP-USR-001",
  "acceptance_criteria_ref": "AC-USR-001-03",
  "test_level": "unit",
  "test_type": "positive",
  "priority": "P0",
  "title": "Create user with valid email returns 201",
  "description": "Verify that POST /api/v1/users with valid name and email creates a new user and returns 201 with the user object.",
  "preconditions": [
    "Database is accessible",
    "No user with email 'test@example.com' exists"
  ],
  "steps": [
    {
      "step": 1,
      "action": "Send POST /api/v1/users with body {name: 'Test User', email: 'test@example.com'}",
      "expected": "Response status 201"
    },
    {
      "step": 2,
      "action": "Parse response body",
      "expected": "Body contains 'id' (UUID), 'name' = 'Test User', 'email' = 'test@example.com', 'created_at' (ISO 8601)"
    }
  ],
  "test_data": {
    "input": { "name": "Test User", "email": "test@example.com" },
    "expected_output": { "status": 201, "body_schema": "schemas/user-response.json" }
  },
  "tags": ["user-management", "create", "happy-path"],
  "generated_by": "qc-agent-vm4",
  "generated_at": "2026-04-07T00:00:00Z"
}
```

### 5.3 Coverage Mapping

Every acceptance criterion must be traceable to at least one test case. The coverage map is maintained as a JSON file:

```json
{
  "blueprint": "BP-USR-001",
  "coverage": [
    {
      "acceptance_criteria": "AC-USR-001-01",
      "test_cases": ["TC-USR-001-01", "TC-USR-001-02"],
      "coverage_status": "covered",
      "test_types": ["positive", "negative"]
    },
    {
      "acceptance_criteria": "AC-USR-001-02",
      "test_cases": [],
      "coverage_status": "uncovered",
      "test_types": []
    }
  ],
  "summary": {
    "total_criteria": 5,
    "covered": 4,
    "uncovered": 1,
    "coverage_pct": 80.0
  }
}
```

**Rule:** Coverage must reach 100% of acceptance criteria before a gate evaluation can proceed. If criteria are uncovered, the QC agent must generate test cases to fill gaps before running the gate.

### 5.4 Edge Case and Negative Scenario Generation

For every positive test case, the QC agent must generate corresponding negative and edge-case tests:

**Systematic edge case categories:**

| Category | Generation Rule | Example |
|----------|----------------|---------|
| Null/empty input | Replace each required field with null, empty string, or omit | `{ "name": null, "email": "" }` |
| Type mismatch | Provide wrong types for each field | `{ "name": 12345, "email": true }` |
| Boundary values | Test at min, min-1, max, max+1 for numeric/string length fields | name with 0, 1, 255, 256 chars |
| Duplicate/conflict | Submit data that conflicts with existing state | Create user with email that already exists |
| Unauthorized access | Call endpoint without auth, with expired token, with wrong role | DELETE /users/123 with read-only token |
| Malformed input | Invalid JSON, missing Content-Type, truncated body | `{ "name": "test"` (missing closing brace) |
| Injection | SQL injection, XSS, command injection in text fields | `{ "name": "'; DROP TABLE users; --" }` |

### 5.5 Boundary Value Analysis

For every numeric parameter or constrained string field:

```
Let min = lower bound, max = upper bound

Test values: [min-1, min, min+1, typical, max-1, max, max+1]

Expected results:
  min-1  → rejection (400 or validation error)
  min    → acceptance
  min+1  → acceptance
  typical → acceptance
  max-1  → acceptance
  max    → acceptance
  max+1  → rejection (400 or validation error)
```

> **Reference:** AI-powered test generation tools like [Testomat.io](https://testomat.io/features/ai-powered-test-case-autogeneration/) emphasize that AI should suggest missing edge-case scenarios to strengthen coverage, complementing human-authored test suites.

---

## 6. Quality Gate Definitions

### 6.1 Gate Dimensions and Thresholds

The quality gate evaluates six dimensions. All thresholds are non-negotiable for PROMOTE decisions.

| # | Dimension | Threshold (PASS) | Warning Zone | Critical Failure (ROLLBACK) | Measurement Method |
|---|-----------|------------------|-------------|---------------------------|-------------------|
| G1 | Code Correctness | ≥ 95% unit test pass rate | 90–94.9% | < 66.5% | `passed / total` from test runner JSON |
| G2 | API Contract Compliance | 100% OpenAPI validation | 95–99.9% | < 70% | Spectral lint + schema validation |
| G3 | Integration Integrity | ≥ 90% integration test pass rate | 80–89.9% | < 63% | `passed / total` from integration suite |
| G4 | Performance Baseline | P95 latency ≤ spec per endpoint | ≤ 150% of spec | > 200% of spec | k6 / artillery benchmark output |
| G5 | Security Compliance | 0 critical, 0 high vulnerabilities | 1–2 medium vulns | ≥ 1 critical or ≥ 3 high | npm audit + semgrep + gitleaks |
| G6 | Test Coverage | ≥ 80% line coverage (P0 modules) | 70–79.9% | < 56% | Coverage tool JSON report |

> **Reference:** The five-dimension quality gate model (Task Success Rate, Context Preservation, P95 Latency, Safety Pass Rate, Evidence Coverage) with PROMOTE/HOLD/ROLLBACK decision logic is adapted from the automated self-testing framework for LLM applications ([arXiv:2603.15676](https://arxiv.org/abs/2603.15676)).

### 6.2 Decision Logic

The gate verdict is computed deterministically from the dimension results:

```
function computeGateVerdict(results):
    criticalFailures = results.filter(r => r.value < r.criticalThreshold)
    warnings = results.filter(r => r.value < r.passThreshold AND r.value >= r.criticalThreshold)
    passes = results.filter(r => r.value >= r.passThreshold)
    
    if criticalFailures.length > 0:
        return "ROLLBACK"
    
    if warnings.length > 0:
        return "HOLD"
    
    if passes.length == results.length:
        return "PROMOTE"
```

**Decision matrix:**

| Scenario | Verdict | Action |
|----------|---------|--------|
| All 6 dimensions ≥ PASS threshold | **PROMOTE** | Notify VM-1 Architect; signal VM-5 Operator for deployment |
| 1+ dimensions in warning zone, 0 in critical | **HOLD** | Notify VM-1 Architect; send detailed defect report to VM-3 Devs; request targeted fix |
| Any dimension below critical threshold | **ROLLBACK** | Notify VM-1 Architect immediately; full defect report to VM-3 Devs; block deployment pipeline |

### 6.3 Gate Enforcement in Lobster Pipeline

The Lobster pipeline orchestrates the gate as a deterministic step in the code-review loop:

```yaml
# Lobster pipeline excerpt: code-review.lobster
pipeline:
  name: code-review-loop
  max_iterations: 3
  
  steps:
    - id: pull-code
      agent: qc-vm4
      action: git_pull
      branch: "{{ branch }}"
    
    - id: run-tests
      agent: qc-vm4
      action: execute_qa_framework
      config:
        levels: [1, 2, 3, 4, 5]
        golden_dataset: "datasets/golden-v{{ dataset_version }}.json"
        report_format: json
    
    - id: evaluate-gate
      agent: qc-vm4
      action: compute_gate_verdict
      input: "{{ steps.run-tests.output }}"
      thresholds:
        code_correctness: { pass: 0.95, critical: 0.665 }
        api_compliance: { pass: 1.0, critical: 0.70 }
        integration_integrity: { pass: 0.90, critical: 0.63 }
        performance_baseline: { pass: 1.0, critical: 0.50 }
        security_compliance: { pass: 1.0, critical: 0.0 }
        test_coverage: { pass: 0.80, critical: 0.56 }
    
    - id: route-verdict
      type: conditional
      conditions:
        - if: "{{ steps.evaluate-gate.verdict == 'PROMOTE' }}"
          goto: promote
        - if: "{{ steps.evaluate-gate.verdict == 'HOLD' }}"
          goto: feedback-to-dev
        - if: "{{ steps.evaluate-gate.verdict == 'ROLLBACK' }}"
          goto: feedback-to-dev
    
    - id: feedback-to-dev
      agent: qc-vm4
      action: generate_defect_report
      input: "{{ steps.run-tests.output }}"
      output_to: vm3-developers
      then:
        if: "{{ iteration < max_iterations }}"
        goto: pull-code
        else: escalate-to-architect
    
    - id: promote
      agent: qc-vm4
      action: emit_promote_signal
      output_to: vm1-architect
    
    - id: escalate-to-architect
      agent: qc-vm4
      action: emit_escalation
      output_to: vm1-architect
      reason: "Max iterations (3) reached without PROMOTE"
```

---

## 7. LLM-as-Judge Evaluation

### 7.1 When to Use LLM-as-Judge

LLM-as-Judge is used when the property being evaluated cannot be reduced to a deterministic check. It complements—never replaces—automated testing.

| Use Case | Why LLM-as-Judge | Why Not Deterministic |
|----------|------------------|----------------------|
| Code review quality | Assessing readability, naming conventions, architecture patterns | No regex can reliably judge "clean code" |
| Spec compliance (semantic) | Does the implementation fulfill the intent of the Blueprint? | Blueprint language is natural language, not formal spec |
| Documentation completeness | Are comments and docs sufficient? | Sufficiency is subjective |
| Error message quality | Are error messages helpful to end users? | "Helpful" requires judgment |
| API design consistency | Does new API follow existing patterns? | Pattern matching across APIs requires understanding |

**When NOT to use LLM-as-Judge:**
- Test pass/fail (use test runner)
- Schema validation (use JSON Schema validator)
- Coverage measurement (use coverage tools)
- Vulnerability detection (use SAST scanners)
- Latency measurement (use benchmark tools)

> **Reference:** LLM-as-Judge treats an LLM as an evaluator that scores or ranks outputs based on instructions, handling open-ended tasks by mimicking human judgment. It requires explicit criteria, chain-of-thought reasoning, and careful calibration against human scores ([Patronus AI](https://www.patronus.ai/llm-testing/llm-as-a-judge)).

### 7.2 Evaluation Rubrics

#### Code Quality Rubric

| Score | Label | Definition | Example Indicators |
|-------|-------|------------|-------------------|
| 5 | Excellent | Production-ready code; follows all project conventions; excellent naming; appropriate error handling; well-documented | Clean separation of concerns, consistent patterns, comprehensive error handling, meaningful variable names |
| 4 | Good | Minor improvements possible; functionally sound; mostly follows conventions | Occasional inconsistent naming, minor missing edge-case handling, adequate but not thorough docs |
| 3 | Acceptable | Functional but needs refactoring; some convention violations; incomplete error handling | Mixed patterns, some long functions, partial error handling, minimal docs |
| 2 | Below Standard | Significant issues; works in happy path only; poor structure | God functions, poor naming, missing error handling, no docs, hard-coded values |
| 1 | Unacceptable | Does not function correctly or has critical design flaws | Broken logic, security vulnerabilities, copy-paste code, no tests |

#### Spec Compliance Rubric (RAG Triad)

This rubric applies the RAG Triad adapted for AI-generated code validation:

> **Reference:** The RAG Triad (Context Relevance, Groundedness, Answer Relevance) can be adapted for code validation: does the implementation match the spec, is the code faithful to the design (no hallucinated APIs), and does the code solve the task requirements ([ML Architects Basel](https://ml-architects.ch/blog_posts/testing_qa_ai_eingineering.html)).

| Dimension | Score 5 | Score 3 | Score 1 |
|-----------|---------|---------|---------|
| **Context Relevance** (implementation matches Blueprint spec) | Every function/class directly maps to a Blueprint requirement | Most code maps to spec; some unexplained additions | Majority of code is unrelated to the spec |
| **Groundedness** (code faithful to design; no hallucinated APIs) | All APIs, schemas, and libraries used are documented in the spec or project dependencies | Some undocumented dependencies but reasonable | Uses non-existent APIs, fabricated library methods, or incompatible versions |
| **Answer Relevance** (code solves the task requirements) | All acceptance criteria met; edge cases handled | Core criteria met; edge cases partially handled | Does not satisfy primary acceptance criteria |

### 7.3 Scoring Schema

```json
{
  "evaluation_id": "EVAL-2026-04-07-001",
  "evaluator": "llm-as-judge",
  "model": "minimax-2.7",
  "target": {
    "file": "src/services/user-service.ts",
    "blueprint_ref": "BP-USR-001",
    "commit": "a1b2c3d"
  },
  "scores": {
    "code_quality": {
      "score": 4,
      "reasoning": "Well-structured service with clear separation of concerns. Minor issue: error handling in createUser() catches generic Error instead of specific exception types. Naming is consistent throughout.",
      "evidence": [
        { "file": "src/services/user-service.ts", "line": 45, "observation": "catch(Error) should be catch(DatabaseError | ValidationError)" }
      ]
    },
    "context_relevance": {
      "score": 5,
      "reasoning": "Every public method maps directly to a Blueprint requirement. No extraneous functionality.",
      "evidence": []
    },
    "groundedness": {
      "score": 4,
      "reasoning": "All APIs used are documented except for a utility function 'slugify' imported from a package not in the spec. The package exists and is appropriate.",
      "evidence": [
        { "file": "src/services/user-service.ts", "line": 3, "observation": "import { slugify } from 'slugify' — not in Blueprint but reasonable addition" }
      ]
    },
    "answer_relevance": {
      "score": 5,
      "reasoning": "All 5 acceptance criteria for BP-USR-001 are satisfied. Edge cases for duplicate email and invalid format are handled.",
      "evidence": []
    }
  },
  "aggregate_score": 4.5,
  "pass": true,
  "threshold": 3.5,
  "chain_of_thought": "Evaluated user-service.ts against BP-USR-001. Checked each public method against acceptance criteria. Verified all imports against project dependencies. Found one minor error handling issue (score 4 on code quality) and one undocumented but appropriate dependency (score 4 on groundedness). Overall: strong implementation."
}
```

### 7.4 Handling Disagreements

When automated tests pass but LLM-as-Judge scores below threshold (or vice versa):

| Automated Tests | LLM-as-Judge | Resolution |
|----------------|-------------|------------|
| PASS | PASS (≥ 3.5) | Normal flow: proceed to gate |
| PASS | FAIL (< 3.5) | Flag for review. Do not auto-ROLLBACK. Include Judge findings in HOLD report. QC agent adds detailed reasoning. |
| FAIL | PASS (≥ 3.5) | Automated tests take precedence. FAIL. Investigate if LLM-as-Judge missed a concrete defect. |
| FAIL | FAIL (< 3.5) | Clear failure. Proceed to defect reporting. |

**Principle:** Automated deterministic tests always take precedence over LLM-as-Judge for FAIL decisions. LLM-as-Judge can only add HOLD conditions, never override a PASS from automated tests into a ROLLBACK.

> **Reference:** LLM-judge disagreements with structural system gates are attributable to different failure modes — latency violations and routing errors invisible in response text vs. content quality failures missed by structural checks — validating the need for multi-dimensional gate design ([arXiv:2603.15676](https://arxiv.org/abs/2603.15676)).

---

## 8. Test Execution Protocol

### 8.1 Pre-Execution Checklist

Before running any test suite, the QC agent must verify all preconditions. Proceed only if all checks pass.

```json
{
  "checklist": [
    {
      "id": "PRE-01",
      "check": "Code is available and current",
      "command": "git pull origin {{ branch }} && git log -1 --format='%H %s'",
      "pass_condition": "Exit code 0 and commit hash matches task assignment"
    },
    {
      "id": "PRE-02",
      "check": "Dependencies installed",
      "command": "npm ci || pip install -r requirements.txt",
      "pass_condition": "Exit code 0, no unresolved dependencies"
    },
    {
      "id": "PRE-03",
      "check": "Test environment is clean",
      "command": "npm run db:reset:test || pytest fixtures --setup",
      "pass_condition": "Exit code 0, test database in known state"
    },
    {
      "id": "PRE-04",
      "check": "Configuration is correct",
      "command": "cat .env.test && validate-env.sh",
      "pass_condition": "All required env vars present, no production values"
    },
    {
      "id": "PRE-05",
      "check": "Golden dataset is loaded",
      "command": "stat datasets/golden-current.json && jq '.entries | length' datasets/golden-current.json",
      "pass_condition": "File exists and entry count ≥ 50"
    },
    {
      "id": "PRE-06",
      "check": "Previous test artifacts cleaned",
      "command": "rm -rf test-results/ && mkdir test-results/",
      "pass_condition": "Clean results directory"
    }
  ]
}
```

### 8.2 Execution Workflow

The QC agent executes tests in a strict sequence. Each level must complete before the next begins. A ROLLBACK at any level short-circuits the remaining levels.

**Procedure:**

1. **Run Pre-Execution Checklist** (Section 8.1)
   - If any check fails → abort and report configuration error to VM-1 Architect
2. **Level 1: Unit Tests**
   - Execute: `exec: pytest tests/unit/ --json-report ...` (or equivalent)
   - Parse results → compute pass rate and coverage
   - If pass rate < critical threshold (66.5%) → skip remaining levels, emit ROLLBACK
3. **Level 2: Integration Tests**
   - Execute API contract validation and integration suite
   - If pass rate < critical threshold (63%) → skip remaining levels, emit ROLLBACK
4. **Level 3: End-to-End Tests**
   - Execute golden dataset scenarios
   - Apply LLM-as-Judge for non-deterministic outputs
5. **Level 4: Performance Tests**
   - Run only if Levels 1-3 pass at HOLD or above
   - Execute benchmark suite
6. **Level 5: Security Tests**
   - Run unconditionally (security issues exist independent of functionality)
   - Execute all security scanners
7. **Aggregate Results**
   - Compile all level results into unified gate report
   - Compute gate verdict (Section 6.2)
8. **Emit Verdict and Reports**
   - Write Test Execution Report (Section 11.1)
   - Write QA Gate Result Report (Section 11.2)
   - If HOLD or ROLLBACK: write Defect Report (Section 11.3)
   - Send reports to appropriate agents via Lobster pipeline

### 8.3 Result Collection and Reporting

All test results must be collected into a unified data structure before gate evaluation:

```json
{
  "run_id": "RUN-2026-04-07-001",
  "timestamp": "2026-04-07T00:42:00Z",
  "commit": "a1b2c3d4e5f6",
  "branch": "feature/user-service",
  "levels": {
    "unit": {
      "total": 150,
      "passed": 147,
      "failed": 2,
      "skipped": 1,
      "error": 0,
      "pass_rate": 0.98,
      "coverage": { "line": 0.84, "branch": 0.72 },
      "duration_ms": 12340,
      "failures": [
        { "test": "test_create_user_duplicate_email", "message": "Expected 409, got 500", "file": "tests/unit/test_user.py:45" },
        { "test": "test_validate_email_format", "message": "AssertionError: regex did not reject 'user@'", "file": "tests/unit/test_user.py:78" }
      ]
    },
    "integration": { "...": "same structure" },
    "e2e": { "...": "same structure" },
    "performance": {
      "endpoints": [
        { "path": "POST /api/v1/users", "p50_ms": 45, "p95_ms": 120, "p99_ms": 210, "spec_p95_ms": 500, "pass": true }
      ],
      "memory_growth_pct": 3.2,
      "error_rate": 0.001
    },
    "security": {
      "critical": 0,
      "high": 0,
      "medium": 2,
      "low": 8,
      "secrets_found": 0,
      "findings": [
        { "severity": "medium", "rule": "javascript.express.no-rate-limit", "file": "src/routes/auth.ts:12", "message": "Rate limiting not configured for auth endpoint" }
      ]
    }
  }
}
```

### 8.4 Defect Reporting Schema

Every defect found during testing must be reported in this structured format:

```json
{
  "defect_id": "DEF-2026-04-07-001",
  "run_id": "RUN-2026-04-07-001",
  "severity": "major",
  "category": "functional",
  "component": "user-service",
  "title": "Duplicate email check returns 500 instead of 409",
  "description": "When creating a user with an email that already exists in the database, the API returns HTTP 500 (Internal Server Error) instead of the expected HTTP 409 (Conflict). The duplicate check query throws an unhandled PostgreSQL unique constraint violation.",
  "blueprint_ref": "BP-USR-001",
  "acceptance_criteria_ref": "AC-USR-001-05",
  "reproduction": {
    "preconditions": ["User with email 'existing@example.com' exists in database"],
    "steps": [
      "POST /api/v1/users with body { name: 'New User', email: 'existing@example.com' }",
      "Observe response status code"
    ],
    "expected": "HTTP 409 with body { error: 'Email already exists' }",
    "actual": "HTTP 500 with body { error: 'Internal Server Error' }"
  },
  "evidence": {
    "test_id": "TC-USR-001-12",
    "test_output": "Expected 409, got 500",
    "log_snippet": "ERROR: duplicate key value violates unique constraint \"users_email_key\"",
    "file": "src/services/user-service.ts",
    "line_range": [42, 55]
  },
  "suggested_fix": "Wrap the database insert in a try/catch that specifically catches unique constraint violations (error code 23505) and returns 409.",
  "fix_priority": "P1",
  "detected_at": "2026-04-07T00:42:00Z",
  "detected_by": "qc-agent-vm4"
}
```

**Severity classification:**

| Severity | Definition | Examples |
|----------|-----------|----------|
| **Critical** | System unusable, data loss, security breach | Crash on startup, SQL injection, auth bypass |
| **Major** | Core feature broken, wrong behavior for primary use case | Wrong HTTP status, data corruption, missing required field |
| **Minor** | Feature works but imperfectly, cosmetic issues | Poor error message, inconsistent naming, minor UI glitch |
| **Trivial** | Negligible impact, code style, documentation typo | Trailing whitespace, TODO comment, unused import |

---

## 9. Iterative Test-Fix Loop

### 9.1 How the Lobster Code-Review Loop Works

The Lobster pipeline implements a bounded retry loop for the dev → test → fix cycle. The QC agent is the loop's gatekeeper.

```
Iteration 1:
  VM-3 Dev pushes code → VM-4 QC runs tests → verdict

  If PROMOTE → exit loop, deploy
  If HOLD/ROLLBACK → VM-4 sends defect report to VM-3

Iteration 2:
  VM-3 Dev pushes fix → VM-4 QC runs tests → verdict

  If PROMOTE → exit loop, deploy
  If HOLD/ROLLBACK → VM-4 sends updated defect report to VM-3

Iteration 3 (FINAL):
  VM-3 Dev pushes fix → VM-4 QC runs tests → verdict

  If PROMOTE → exit loop, deploy
  If HOLD/ROLLBACK → ESCALATE to VM-1 Architect
```

**Maximum iterations: 3.** After 3 failed attempts, the task is escalated to the System Architect (VM-1) for re-scoping, re-assignment, or architectural intervention.

### 9.2 QC Agent's Role in Each Iteration

| Iteration | QC Agent Action | Focus |
|-----------|----------------|-------|
| 1 (First pass) | Full test suite across all 5 levels | Comprehensive initial assessment |
| 2 (First fix) | Full suite + focused regression on previously failed tests | Verify fixes; ensure no regressions introduced |
| 3 (Second fix) | Full suite + focused regression + escalation preparation | Final chance; prepare detailed escalation report if still failing |

### 9.3 Feedback Format for Developers

The defect report sent to VM-3 Developers after a HOLD or ROLLBACK must follow this structure:

```json
{
  "feedback_id": "FB-2026-04-07-001",
  "iteration": 1,
  "max_iterations": 3,
  "verdict": "HOLD",
  "summary": "4 of 6 gates pass. 2 gates in warning zone. 0 critical failures.",
  "gate_results": {
    "code_correctness": { "value": 0.98, "status": "PASS" },
    "api_compliance": { "value": 0.97, "status": "WARNING" },
    "integration_integrity": { "value": 0.88, "status": "WARNING" },
    "performance_baseline": { "value": 1.0, "status": "PASS" },
    "security_compliance": { "value": 1.0, "status": "PASS" },
    "test_coverage": { "value": 0.82, "status": "PASS" }
  },
  "defects": [
    {
      "defect_id": "DEF-2026-04-07-001",
      "severity": "major",
      "title": "Duplicate email check returns 500 instead of 409",
      "fix_priority": "P1",
      "suggested_fix": "Wrap database insert in try/catch for unique constraint violations"
    }
  ],
  "action_required": "Fix defects listed above and re-push to branch feature/user-service. Focus on P1 items first.",
  "previous_iteration_defects_resolved": [],
  "previous_iteration_defects_unresolved": [],
  "new_defects_this_iteration": ["DEF-2026-04-07-001"]
}
```

### 9.4 Convergence Criteria

The loop converges (PROMOTE) when all six gate dimensions meet their PASS thresholds simultaneously in a single run. Partial convergence (some gates improved, others regressed) resets no counters — the iteration count only increments.

**Convergence indicators tracked across iterations:**

| Metric | Healthy Trend | Unhealthy Trend (escalation signal) |
|--------|--------------|-------------------------------------|
| Total defects | Decreasing each iteration | Flat or increasing |
| Gate scores | Monotonically improving | Oscillating or decreasing |
| New defects introduced | 0 per iteration | > 0 (fixes introduce regressions) |
| Fix rate | ≥ 80% of reported defects fixed per iteration | < 50% of defects addressed |

---

## 10. Regression Testing Strategy

### 10.1 When to Run Regression

| Trigger | Regression Scope | Rationale |
|---------|-----------------|-----------|
| Every code push (PR) | Minimal regression set (Tier 1 golden dataset + all unit tests) | Fast feedback; catch obvious regressions |
| Pre-gate evaluation | Full regression suite (all tiers of golden dataset) | Complete assessment before gate decision |
| Nightly build | Full regression + performance benchmarks | Catch slow-building issues; establish trending baselines |
| Pre-release | Full regression + security scan + extended E2E | Final verification before production |
| Post-model-upgrade | Full regression + LLM-as-Judge re-calibration | Model changes can shift behavior subtly |

### 10.2 Minimal Regression Set vs Full Suite

**Minimal regression set** (target execution time: < 5 minutes):
- All unit tests
- Core Functional tier from golden dataset (40% of entries)
- API contract validation
- Critical path E2E scenarios (top 10 user journeys)

**Full regression suite** (target execution time: < 30 minutes):
- All unit tests
- All integration tests
- Full golden dataset (all 4 tiers)
- Performance benchmarks (abbreviated: 1-minute load test)
- Full security scan

### 10.3 Flaky Test Identification and Quarantine

A test is **flaky** if it produces different results on the same code within a short time window.

**Detection:**
1. Track pass/fail history per test across the last 10 runs
2. A test is flagged as flaky if its pass rate is between 10% and 90% (not consistently passing or failing)
3. Compute flakiness score: `1 - |2 * pass_rate - 1|` (0 = stable, 1 = maximally flaky)

**Quarantine protocol:**
1. Flaky test is moved to a `quarantine/` directory
2. It is excluded from gate calculations (does not count toward pass rate)
3. It continues to run for monitoring but its result is logged, not gated
4. A defect is opened: "Flaky test: [test_id] — investigate root cause"
5. After the root cause is fixed, the test is moved back to the active suite and monitored for 5 consecutive stable runs before it counts toward gates again

```json
{
  "quarantine_registry": [
    {
      "test_id": "TC-USR-003-07",
      "quarantined_at": "2026-04-05T10:00:00Z",
      "reason": "Intermittent timeout on database connection in CI",
      "pass_rate_last_10": 0.6,
      "flakiness_score": 0.8,
      "defect_id": "DEF-2026-04-05-003",
      "status": "investigating"
    }
  ]
}
```

### 10.4 Test Result Trending and Drift Detection

The QC agent maintains a rolling window of test metrics across the last 20 runs:

**Tracked metrics:**
| Metric | Alert Condition |
|--------|----------------|
| Unit test pass rate | Downward trend > 2% over 5 consecutive runs |
| Integration test pass rate | Downward trend > 3% over 5 consecutive runs |
| Average P95 latency | Upward trend > 10% over 5 consecutive runs |
| Coverage | Downward trend > 3% over 5 consecutive runs |
| Flaky test count | Increase > 3 in a single week |
| New defect density | Increase > 20% over rolling 5-run average |

**Drift detection algorithm:**
```
For each metric M over window W (last 5 runs):
  slope = linear_regression(M values over W).slope
  if slope direction is adverse AND magnitude > alert_threshold:
    emit WARNING: "Quality drift detected: {metric} trending {direction} by {magnitude} over last {W} runs"
    include in next QA Gate Result Report
```

---

## 11. Structured Report Templates

All reports are JSON. Every report is written to the `test-results/` directory and transmitted to the requesting agent via the Lobster pipeline.

### 11.1 Test Execution Report

Produced after every test run. Contains raw results from all test levels.

```json
{
  "$schema": "gateforge://schemas/test-execution-report-v1.json",
  "report_type": "test_execution",
  "report_id": "TER-2026-04-07-001",
  "run_id": "RUN-2026-04-07-001",
  "timestamp": "2026-04-07T00:42:00Z",
  "pipeline": {
    "name": "code-review-loop",
    "iteration": 1,
    "max_iterations": 3,
    "task_id": "TASK-2026-04-07-USR-001"
  },
  "source": {
    "branch": "feature/user-service",
    "commit": "a1b2c3d4e5f6",
    "commit_message": "feat: implement user CRUD endpoints",
    "author": "vm3-developer"
  },
  "environment": {
    "vm": "vm-4",
    "model": "minimax-2.7",
    "runtime": "node-20.11.0",
    "os": "ubuntu-22.04"
  },
  "pre_execution_checklist": {
    "all_passed": true,
    "checks": [
      { "id": "PRE-01", "status": "pass", "detail": "Commit a1b2c3d matches task" },
      { "id": "PRE-02", "status": "pass", "detail": "npm ci completed" },
      { "id": "PRE-03", "status": "pass", "detail": "Test DB reset" },
      { "id": "PRE-04", "status": "pass", "detail": "All env vars present" },
      { "id": "PRE-05", "status": "pass", "detail": "Golden dataset: 127 entries" },
      { "id": "PRE-06", "status": "pass", "detail": "Results directory clean" }
    ]
  },
  "results": {
    "level_1_unit": {
      "status": "completed",
      "total": 150,
      "passed": 147,
      "failed": 2,
      "skipped": 1,
      "error": 0,
      "pass_rate": 0.98,
      "duration_ms": 12340,
      "coverage": {
        "line": 0.84,
        "branch": 0.72,
        "function": 0.91,
        "p0_module_line": 0.87
      },
      "failures": [
        {
          "test_id": "test_create_user_duplicate_email",
          "file": "tests/unit/test_user.py:45",
          "message": "Expected 409, got 500",
          "stack_trace": "AssertionError at test_user.py:47"
        },
        {
          "test_id": "test_validate_email_format",
          "file": "tests/unit/test_user.py:78",
          "message": "Regex did not reject 'user@'",
          "stack_trace": "AssertionError at test_user.py:80"
        }
      ]
    },
    "level_2_integration": {
      "status": "completed",
      "total": 45,
      "passed": 40,
      "failed": 4,
      "skipped": 1,
      "error": 0,
      "pass_rate": 0.889,
      "duration_ms": 34200,
      "api_contract_validation": {
        "total_endpoints": 12,
        "compliant": 12,
        "violations": 0,
        "compliance_rate": 1.0
      },
      "failures": []
    },
    "level_3_e2e": {
      "status": "completed",
      "total": 30,
      "passed": 27,
      "failed": 3,
      "skipped": 0,
      "error": 0,
      "pass_rate": 0.90,
      "duration_ms": 65000,
      "golden_dataset_results": {
        "tier_core": { "total": 12, "passed": 12, "rate": 1.0 },
        "tier_complex": { "total": 8, "passed": 7, "rate": 0.875 },
        "tier_edge": { "total": 6, "passed": 5, "rate": 0.833 },
        "tier_adversarial": { "total": 4, "passed": 3, "rate": 0.75 }
      }
    },
    "level_4_performance": {
      "status": "completed",
      "endpoints": [
        {
          "path": "POST /api/v1/users",
          "p50_ms": 45,
          "p95_ms": 120,
          "p99_ms": 210,
          "spec_p95_ms": 500,
          "pass": true
        },
        {
          "path": "GET /api/v1/users/:id",
          "p50_ms": 12,
          "p95_ms": 35,
          "p99_ms": 78,
          "spec_p95_ms": 200,
          "pass": true
        }
      ],
      "memory_growth_pct": 3.2,
      "error_rate_under_load": 0.001,
      "duration_ms": 120000
    },
    "level_5_security": {
      "status": "completed",
      "vulnerabilities": {
        "critical": 0,
        "high": 0,
        "medium": 2,
        "low": 8,
        "info": 15
      },
      "secrets_found": 0,
      "findings": [
        {
          "id": "SEC-001",
          "severity": "medium",
          "tool": "semgrep",
          "rule": "javascript.express.no-rate-limit",
          "file": "src/routes/auth.ts",
          "line": 12,
          "message": "Rate limiting not configured for authentication endpoint"
        },
        {
          "id": "SEC-002",
          "severity": "medium",
          "tool": "npm-audit",
          "package": "lodash@4.17.20",
          "cve": "CVE-2021-23337",
          "message": "Prototype pollution in lodash.template"
        }
      ],
      "duration_ms": 45000
    }
  },
  "llm_as_judge": {
    "evaluations_performed": 3,
    "aggregate_score": 4.25,
    "threshold": 3.5,
    "pass": true,
    "details": [
      {
        "target": "src/services/user-service.ts",
        "code_quality": 4,
        "context_relevance": 5,
        "groundedness": 4,
        "answer_relevance": 5
      }
    ]
  },
  "summary": {
    "total_tests_all_levels": 225,
    "total_passed": 214,
    "total_failed": 9,
    "total_skipped": 2,
    "overall_pass_rate": 0.951,
    "total_duration_ms": 276540
  }
}
```

### 11.2 QA Gate Result Report

Produced after gate evaluation. This is the authoritative document for the PROMOTE/HOLD/ROLLBACK decision.

```json
{
  "$schema": "gateforge://schemas/qa-gate-result-v1.json",
  "report_type": "qa_gate_result",
  "report_id": "GR-2026-04-07-001",
  "run_id": "RUN-2026-04-07-001",
  "test_execution_report_id": "TER-2026-04-07-001",
  "timestamp": "2026-04-07T00:45:00Z",
  "verdict": "HOLD",
  "pipeline": {
    "name": "code-review-loop",
    "iteration": 1,
    "max_iterations": 3,
    "task_id": "TASK-2026-04-07-USR-001"
  },
  "gate_dimensions": [
    {
      "dimension": "code_correctness",
      "metric": "unit_test_pass_rate",
      "value": 0.98,
      "threshold_pass": 0.95,
      "threshold_critical": 0.665,
      "status": "PASS"
    },
    {
      "dimension": "api_contract_compliance",
      "metric": "openapi_validation_rate",
      "value": 1.0,
      "threshold_pass": 1.0,
      "threshold_critical": 0.70,
      "status": "PASS"
    },
    {
      "dimension": "integration_integrity",
      "metric": "integration_test_pass_rate",
      "value": 0.889,
      "threshold_pass": 0.90,
      "threshold_critical": 0.63,
      "status": "WARNING"
    },
    {
      "dimension": "performance_baseline",
      "metric": "p95_latency_within_spec",
      "value": 1.0,
      "threshold_pass": 1.0,
      "threshold_critical": 0.50,
      "status": "PASS"
    },
    {
      "dimension": "security_compliance",
      "metric": "critical_high_vuln_count",
      "value": 0,
      "threshold_pass": 0,
      "threshold_critical": 1,
      "status": "PASS",
      "note": "2 medium vulns present (within tolerance)"
    },
    {
      "dimension": "test_coverage",
      "metric": "p0_module_line_coverage",
      "value": 0.87,
      "threshold_pass": 0.80,
      "threshold_critical": 0.56,
      "status": "PASS"
    }
  ],
  "gate_summary": {
    "total_dimensions": 6,
    "passed": 5,
    "warning": 1,
    "critical_failure": 0
  },
  "verdict_reasoning": "5 of 6 gates pass. Integration integrity at 88.9% is below the 90% PASS threshold but above the 63% critical threshold. Verdict: HOLD. Developer action required to fix 4 failing integration tests.",
  "action": {
    "target_agent": "vm3-developers",
    "action_type": "fix_and_resubmit",
    "focus_areas": ["integration test failures"],
    "defect_report_id": "DR-2026-04-07-001",
    "remaining_iterations": 2
  },
  "trend": {
    "previous_run_verdict": null,
    "improvement_from_previous": null,
    "notes": "First iteration — no previous data"
  }
}
```

### 11.3 Defect Report

Produced when any defects are found during testing. Groups all defects from a single run.

```json
{
  "$schema": "gateforge://schemas/defect-report-v1.json",
  "report_type": "defect_report",
  "report_id": "DR-2026-04-07-001",
  "run_id": "RUN-2026-04-07-001",
  "timestamp": "2026-04-07T00:45:00Z",
  "pipeline": {
    "name": "code-review-loop",
    "iteration": 1,
    "task_id": "TASK-2026-04-07-USR-001"
  },
  "summary": {
    "total_defects": 3,
    "by_severity": { "critical": 0, "major": 2, "minor": 1, "trivial": 0 },
    "by_category": { "functional": 2, "security": 1 },
    "blocking_promotion": true
  },
  "defects": [
    {
      "defect_id": "DEF-2026-04-07-001",
      "severity": "major",
      "category": "functional",
      "component": "user-service",
      "title": "Duplicate email check returns 500 instead of 409",
      "description": "When creating a user with an email that already exists in the database, the API returns HTTP 500 instead of the expected HTTP 409.",
      "blueprint_ref": "BP-USR-001",
      "acceptance_criteria_ref": "AC-USR-001-05",
      "reproduction": {
        "preconditions": ["User with email 'existing@example.com' exists"],
        "steps": ["POST /api/v1/users with body { name: 'New User', email: 'existing@example.com' }"],
        "expected": "HTTP 409 with error body",
        "actual": "HTTP 500"
      },
      "evidence": {
        "test_id": "test_create_user_duplicate_email",
        "log_snippet": "ERROR: duplicate key value violates unique constraint"
      },
      "suggested_fix": "Add try/catch for PostgreSQL error code 23505 in createUser()",
      "fix_priority": "P1"
    },
    {
      "defect_id": "DEF-2026-04-07-002",
      "severity": "major",
      "category": "functional",
      "component": "user-service",
      "title": "Email validation regex does not reject 'user@' (missing domain)",
      "description": "The email format validator accepts 'user@' as a valid email address. The regex is missing the domain part check.",
      "blueprint_ref": "BP-USR-001",
      "acceptance_criteria_ref": "AC-USR-001-02",
      "reproduction": {
        "preconditions": [],
        "steps": ["Call validateEmail('user@')"],
        "expected": "Return false",
        "actual": "Returns true"
      },
      "evidence": {
        "test_id": "test_validate_email_format",
        "file": "src/utils/validators.ts",
        "line": 15
      },
      "suggested_fix": "Update regex to require at least one character after @: /^[^@]+@[^@]+\\.[^@]+$/",
      "fix_priority": "P1"
    },
    {
      "defect_id": "DEF-2026-04-07-003",
      "severity": "minor",
      "category": "security",
      "component": "auth-routes",
      "title": "No rate limiting on authentication endpoint",
      "description": "The POST /api/v1/auth/login endpoint has no rate limiting configured, making it vulnerable to brute-force attacks.",
      "blueprint_ref": "BP-AUTH-001",
      "reproduction": {
        "preconditions": [],
        "steps": ["Send 1000 rapid login requests"],
        "expected": "Rate limit after ~10 attempts (429 Too Many Requests)",
        "actual": "All 1000 requests processed"
      },
      "evidence": {
        "tool": "semgrep",
        "rule": "javascript.express.no-rate-limit"
      },
      "suggested_fix": "Add express-rate-limit middleware to auth routes with max 10 attempts per minute per IP",
      "fix_priority": "P2"
    }
  ],
  "action_required": {
    "target": "vm3-developers",
    "instructions": "Fix P1 defects first (DEF-001, DEF-002). P2 defect (DEF-003) recommended but not blocking. Re-push to feature/user-service branch when ready.",
    "deadline_iteration": 2
  }
}
```

### 11.4 Regression Report

Produced after regression test runs. Compares current results against the baseline.

```json
{
  "$schema": "gateforge://schemas/regression-report-v1.json",
  "report_type": "regression_report",
  "report_id": "RR-2026-04-07-001",
  "run_id": "RUN-2026-04-07-001",
  "timestamp": "2026-04-07T00:50:00Z",
  "baseline": {
    "run_id": "RUN-2026-04-06-003",
    "commit": "f6e5d4c3b2a1",
    "verdict": "PROMOTE"
  },
  "current": {
    "commit": "a1b2c3d4e5f6",
    "branch": "feature/user-service"
  },
  "comparison": {
    "unit_test_pass_rate": { "baseline": 1.0, "current": 0.98, "delta": -0.02, "status": "regression" },
    "integration_pass_rate": { "baseline": 0.95, "current": 0.889, "delta": -0.061, "status": "regression" },
    "e2e_pass_rate": { "baseline": 0.93, "current": 0.90, "delta": -0.03, "status": "regression" },
    "p95_latency_avg_ms": { "baseline": 110, "current": 120, "delta": 10, "status": "stable" },
    "line_coverage": { "baseline": 0.82, "current": 0.84, "delta": 0.02, "status": "improvement" },
    "security_critical_high": { "baseline": 0, "current": 0, "delta": 0, "status": "stable" }
  },
  "regressions": [
    {
      "metric": "unit_test_pass_rate",
      "severity": "minor",
      "detail": "2 new test failures introduced",
      "affected_tests": ["test_create_user_duplicate_email", "test_validate_email_format"]
    },
    {
      "metric": "integration_pass_rate",
      "severity": "major",
      "detail": "4 integration tests now failing that passed in baseline",
      "affected_tests": ["test_user_creation_flow", "test_user_update_flow", "test_user_list_pagination", "test_user_delete_cascade"]
    }
  ],
  "improvements": [
    {
      "metric": "line_coverage",
      "detail": "Coverage improved from 82% to 84% with new user-service tests"
    }
  ],
  "new_tests": {
    "added": 15,
    "test_ids": ["TC-USR-001-01", "TC-USR-001-02", "..."]
  },
  "flaky_tests": {
    "currently_quarantined": 1,
    "newly_flagged": 0,
    "resolved": 0
  },
  "drift_alerts": [],
  "verdict": "Regressions detected in unit and integration test pass rates. 2 major, 1 minor regression. No improvements offset the regressions."
}
```

---

## 12. Continuous Improvement

### 12.1 Post-Release Defect Analysis (Escaped Defects)

An **escaped defect** is a bug that reaches production despite passing through the QA gate. Every escaped defect is a framework failure that must be analyzed and prevented from recurring.

**Procedure:**

1. When an escaped defect is reported (by VM-5 Operator or external feedback):
   - Create an escaped-defect record:
     ```json
     {
       "escaped_defect_id": "ED-2026-04-07-001",
       "production_incident": "INC-2026-04-07-042",
       "severity": "major",
       "description": "Users with unicode names cause encoding error in search",
       "root_cause": "QA golden dataset contained only ASCII names",
       "gate_that_should_have_caught": "G1 (Code Correctness) or G3 (Integration Integrity)",
       "why_it_escaped": "No unicode test cases in golden dataset; boundary value analysis did not cover encoding",
       "corrective_actions": [
         "Add 10 golden dataset entries with unicode names (CJK, Arabic, emoji, accented characters)",
         "Add boundary test for max UTF-8 byte length",
         "Update test generation protocol to mandate encoding edge cases for all text fields"
       ],
       "golden_dataset_entries_added": ["GD-0128", "GD-0129", "GD-0130", "GD-0131", "GD-0132", "GD-0133", "GD-0134", "GD-0135", "GD-0136", "GD-0137"],
       "resolved_at": "2026-04-08T00:00:00Z"
     }
     ```
2. Add golden dataset entries that would have caught the defect
3. Update the test generation protocol if a category of test was systematically missing
4. Re-run the full regression suite to verify the new tests catch the defect

### 12.2 Golden Dataset Expansion from Production Incidents

Every production incident must result in at least one new golden dataset entry. This ensures the dataset evolves to cover real-world failure modes, not just theoretical ones.

**Expansion rule:** For each escaped defect, add entries to at least 2 tiers:
- **Core Functional:** The direct happy-path variant that should work
- **Edge Case:** The specific input that triggered the failure

### 12.3 Test Effectiveness Metrics

Track these metrics monthly to evaluate the framework's health:

| Metric | Formula | Target | Action if Below Target |
|--------|---------|--------|----------------------|
| Defect Detection Rate (DDR) | Defects found by QA / (Defects found by QA + Escaped defects) | ≥ 95% | Expand golden dataset; review test generation gaps |
| False Positive Rate (FPR) | Tests that fail but code is correct / Total test failures | ≤ 5% | Investigate and fix flaky tests; tighten test precision |
| Mean Iterations to PROMOTE | Average loop iterations before PROMOTE | ≤ 1.5 | Improve defect report clarity; provide better fix suggestions |
| Gate Override Rate | Manual PROMOTE overrides / Total gate decisions | ≤ 2% | Review override reasons; adjust thresholds if systematically wrong |
| Escaped Defect Rate | Escaped defects per release | ≤ 1 per release | Root-cause analysis; framework revision |
| Test Suite Growth Rate | New tests added per sprint | Positive | Ensure generation protocol is active |

### 12.4 Framework Versioning and Evolution

This framework is a living document. Changes are tracked with semantic versioning:

| Version Change | When | Examples |
|---------------|------|----------|
| **Patch** (1.0.x) | Threshold tuning, template fixes, typo corrections | Adjust G3 threshold from 90% to 88% based on data |
| **Minor** (1.x.0) | New test types, new report fields, new tools | Add GraphQL contract validation; add mutation testing |
| **Major** (x.0.0) | Structural changes to gate logic, new dimensions, schema breaks | Add 7th gate dimension; change verdict logic |

**Change protocol:**
1. Propose change with rationale (data-driven, referencing escaped defects or effectiveness metrics)
2. VM-1 Architect approves
3. Update this document
4. Update all Lobster pipeline configs that reference changed thresholds
5. Notify all agents of the change

---

## 13. Appendix

### A. Quality Gate Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│              GATEFORGE QUALITY GATE — QUICK REFERENCE           │
├──────────────────────┬──────────┬───────────┬───────────────────┤
│ Dimension            │ PASS     │ WARNING   │ ROLLBACK          │
├──────────────────────┼──────────┼───────────┼───────────────────┤
│ G1 Code Correctness  │ ≥ 95%    │ 90–94.9%  │ < 66.5%           │
│ G2 API Compliance    │ 100%     │ 95–99.9%  │ < 70%             │
│ G3 Integration       │ ≥ 90%    │ 80–89.9%  │ < 63%             │
│ G4 Performance       │ ≤ spec   │ ≤ 150%    │ > 200% of spec    │
│ G5 Security          │ 0 crit/h │ 1–2 med   │ ≥ 1 crit or ≥ 3h │
│ G6 Test Coverage     │ ≥ 80%    │ 70–79.9%  │ < 56%             │
├──────────────────────┴──────────┴───────────┴───────────────────┤
│ VERDICT LOGIC:                                                  │
│   All PASS           → PROMOTE  (deploy to production)          │
│   Any WARNING        → HOLD     (fix and resubmit, ≤3 loops)   │
│   Any ROLLBACK       → ROLLBACK (immediate rejection)           │
├─────────────────────────────────────────────────────────────────┤
│ MAX ITERATIONS: 3    │ ESCALATION: VM-1 Architect               │
└─────────────────────────────────────────────────────────────────┘
```

### B. Test Type Cheat Sheet

| Test Type | Level | Deterministic? | Typical Count | Execution Time | Tools |
|-----------|-------|---------------|---------------|----------------|-------|
| Unit test | L1 | Yes | 100–500 | < 30s | pytest, jest, vitest |
| API contract validation | L2 | Yes | 10–50 | < 10s | spectral, ajv |
| Integration test | L2 | Yes | 30–100 | 1–5 min | pytest, supertest |
| E2E scenario | L3 | Mixed | 20–100 | 5–15 min | playwright, cypress |
| Golden dataset eval | L3 | Mixed | 50–500 | 5–30 min | custom runner |
| LLM-as-Judge eval | L3 | No | 5–20 | 1–5 min | minimax-2.7 |
| Load test | L4 | Yes | 3–10 scenarios | 5–15 min | k6, artillery |
| SAST scan | L5 | Yes | Full codebase | 1–5 min | semgrep |
| Dependency audit | L5 | Yes | All deps | < 30s | npm audit, pip-audit |
| Secret scan | L5 | Yes | Full repo | < 30s | gitleaks |

### C. Severity Classification Guide

| Severity | Impact | SLA (fix deadline) | Gate Impact | Examples |
|----------|--------|-------------------|-------------|----------|
| **Critical (P0)** | System down, data loss, security breach | Fix immediately; blocks all work | Automatic ROLLBACK | Crash on startup, auth bypass, data corruption, exposed secrets |
| **Major (P1)** | Core feature broken, wrong behavior | Fix within current iteration | Blocks PROMOTE | Wrong HTTP status, missing validation, broken workflow |
| **Minor (P2)** | Feature works imperfectly | Fix within next 2 iterations | Warning only | Poor error messages, inconsistent response format, minor UI issues |
| **Trivial (P3)** | Negligible impact | Fix when convenient | No gate impact | Code style, unused imports, documentation typos |

### D. Glossary

| Term | Definition |
|------|-----------|
| **Blueprint** | The specification document produced by VM-2 System Designer that defines what the code must do |
| **Golden Dataset** | A curated set of test inputs and expected outputs used as the ground truth for evaluation |
| **Gate** | A checkpoint that code must pass before proceeding to the next pipeline stage |
| **Gate Dimension** | One of the six measurable quality aspects evaluated at a gate |
| **HOLD** | Gate verdict indicating the build nearly passes but needs targeted fixes |
| **Lobster Pipeline** | The deterministic YAML-based orchestration system that routes tasks between agents |
| **LLM-as-Judge** | Using an LLM (MiniMax 2.7) to evaluate subjective quality aspects against a rubric |
| **PROMOTE** | Gate verdict indicating the build is ready for deployment |
| **QC Agent** | Quality Control agent running on VM-4, responsible for all testing and gating |
| **RAG Triad** | Three evaluation dimensions: Context Relevance, Groundedness, Answer Relevance |
| **ROLLBACK** | Gate verdict indicating the build has critical failures and must not proceed |
| **Stratification** | Dividing the golden dataset into tiers to ensure diverse test coverage |
| **Flaky Test** | A test that non-deterministically passes or fails on the same code |
| **Escaped Defect** | A bug that passes through QA and reaches production |
| **DDR** | Defect Detection Rate — the proportion of all defects caught by QA |
| **FPR** | False Positive Rate — the proportion of test failures that are not real bugs |
| **P95 Latency** | The 95th percentile response time — 95% of requests are faster than this value |
| **Convergence** | The test-fix loop reaching a state where all gates pass simultaneously |

---

---

## Appendix: Managed Output Documents

QC agents produce and maintain the following documents in the Blueprint repository's `qa/` directory.

### Document Ownership Map

| Document | Path in Blueprint Repo | When to Create | When to Update |
|----------|----------------------|----------------|----------------|
| Master Test Plan | `qa/test-plan.md` | At project start | When new modules added or test strategy changes |
| Test Cases | `qa/test-cases/TC-<module>-<type>-<NNN>.md` | When assigned a test task for a module | When requirements change or new test scenarios identified |
| Load Test Plan | `qa/performance/load-test-plan.md` | When NFR performance targets are defined | When targets change or new endpoints added |
| Stress Test Plan | `qa/performance/stress-test-plan.md` | After load test plan is stable | When breaking point criteria change |
| Test Reports | `qa/reports/TEST-REPORT-ITER-<NNN>-<module>.md` | After every test execution cycle | N/A (each report is a new file) |
| QA Metrics | `qa/metrics.md` | At first test execution | After every test execution (living document) |
| Defect Reports | `qa/defects/DEF-<NNN>.md` | When a defect is found | Through defect lifecycle (reported → verified → closed) |

### Output Rules

1. **Use the templates** from `gateforge-blueprint-template/qa/` (`tonylnng/gateforge-blueprint-template`, read-only) — do not invent new formats
2. **Every test report must include a gate assessment**: PROMOTE / HOLD / ROLLBACK with rationale
3. **Defect reports must follow the full lifecycle**: reported → confirmed → in-progress → fixed → verified → closed
4. **QA metrics must be updated** after every test execution — this is a living dashboard
5. **Structured report to Architect**: After every test cycle, produce:

```json
{
  "taskId": "TASK-NNN",
  "type": "testing",
  "status": "completed",
  "module": "auth",
  "testLevels": ["unit", "integration", "e2e"],
  "results": {
    "unit": { "total": 45, "pass": 44, "fail": 1, "skip": 0, "coverage": 96.2 },
    "integration": { "total": 18, "pass": 17, "fail": 1, "skip": 0, "coverage": 91.0 },
    "e2e": { "total": 8, "pass": 7, "fail": 1, "skip": 0, "coverage": 87.5 }
  },
  "gateDecision": "HOLD",
  "gateRationale": "1 integration test failing on token refresh edge case",
  "defectsFound": ["DEF-005", "DEF-006"],
  "documentsUpdated": [
    "qa/reports/TEST-REPORT-ITER-001-auth.md",
    "qa/metrics.md",
    "qa/defects/DEF-005.md",
    "qa/defects/DEF-006.md"
  ],
  "performanceBaseline": {
    "p95Latency": "145ms",
    "throughput": "1200 req/s"
  }
}
```

6. **Git commit convention**: `test(<module>): <description>` (e.g., `test(auth): add JWT refresh token edge case tests`)
7. **Traceability**: Every test case must reference the FR-ID or NFR-ID it validates. Every defect must reference the test case that found it.

---

> **Document end.** This framework is maintained by the QC agents on VM-4 under the governance of the System Architect (VM-1). All changes require Architect approval and must be version-tracked.
