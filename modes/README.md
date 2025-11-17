# 💡 LLM Software Engineering Modes

This directory contains a suite of custom `.chatmode.md` prompt files that define distinct roles for AI agents in a high-discipline, multi-phase software engineering workflow. Each mode is a self-contained persona designed to perform a specific task in the lifecycle of building, testing, and verifying software — from idea to implementation.

---

## 🧱 System Overview

This framework supports AI-assisted software delivery through **role-based automation** and **explicit handoffs** between phases. It enables:

- Modular thinking
- Reusable task scaffolding
- Test-first implementation
- Verifiable output with traceable coverage

Every mode works on specific inputs, produces outputs, and feeds the next mode in the sequence.

---

## 🧩 Available Modes

### `architect.chatmode.md` — **The Planner of Truth**

**Role:** Software Architect
**Responsibility:** Defines a complete, unambiguous spec based on user goals.
**Output:** `./docs/spec/spec.md`

- Clarifies requirements and tradeoffs
- Designs modular, secure architecture
- Adds `## Behavioral Assertions` to the spec
- Hands off to **Doc Writer**, **Spec Tester**, and **Planner**

---

### `docwriter.chatmode.md` — **The UX Clarifier**

**Role:** Technical Documentation Writer
**Responsibility:** Writes user-facing docs before implementation.
**Output:** `./docs/README.md`, `api.md`, or module docs

- Helps validate system behavior and usage
- Surfaces UX or configuration edge cases early
- Can feed gaps back to Architect for spec refinement

---

### `spectester.chatmode.md` — **The Spec-to-Test Translator**

**Role:** Spec Test Generator
**Responsibility:** Converts the finalized spec into automated, runnable behavioral tests.
**Output:** `./tests/spec_tests/*.spec.ts` or equivalent
**Feedback:** `./docs/spec/spec-feedback.md` if any gaps are found

- Covers acceptance criteria, edge cases, and error handling
- Fails early if the spec is incomplete or ambiguous
- Creates a test contract for the Planner, Coder, and Verifier

---

### `planner.chatmode.md` — **The Task Scaffolder**

**Role:** Technical Task Planner
**Responsibility:** Breaks the spec into sequenced, atomic implementation tasks.
**Output:** `./.llm/tasks.md`

- Defines parent/subtasks with rationale
- Ensures work is reviewable, traceable, and logically ordered
- Tightly linked to both spec and prewritten spec tests

---

### `infraengineer.chatmode.md` — **The Infrastructure Builder**

**Role:** Infrastructure-as-Code Engineer
**Responsibility:** Implements the infrastructure needed for the system.
**Output:** `./infra/`, `.github/workflows/`, `secrets.md`

- Provisions resources using Terraform or other IaC tools
- Writes CI/CD pipelines and environment isolation
- Ensures deployment, secrets, and monitoring are defined

---

### `coder.chatmode.md` — **The TDD Executor**

**Role:** Test-Driven Development Implementer
**Responsibility:** Executes one task at a time using strict TDD discipline.
**Output:** Codebase changes, following `./.llm/tasks.md`

- Always writes docs and tests before implementation
- Makes exactly two commits per task (test + code)
- Works top-down on the checklist
- Aligns behavior with prewritten spec tests

---

### `verifier.chatmode.md` — **The Code Auditor**

**Role:** Verifier
**Responsibility:** Validates that implementation matches the spec, task list, and tests.
**Output:** `./docs/spec/spec-feedback.md` if issues are found

- Reviews code quality, task completeness, and spec coverage
- Uses behavioral and task-derived tests to confirm correctness
- Flags any mismatches, missing behaviors, or deviations

---

## 🔁 End-to-End Flow

```

Architect
↓
Doc Writer ←→ Architect (if UX unclear)
↓
Spec Test Generator ←→ Architect (if test gaps found)
↓
Planner ←→ Architect (if tasks are blocked by missing spec info)
↓
Infrastructure Engineer (parallel)
↓
Coder (executes plan via TDD)
↓
Verifier (final QA + spec alignment)

```

---

## 🚦 How Feedback Works

Any role encountering ambiguity or incompleteness in the spec must:

1. Log findings in `./docs/spec/spec-feedback.md`
2. Notify the Architect
3. Await spec update before continuing

This keeps correctness and traceability central to the process.

---

## ✅ Best Practices

- Keep mode prompts versioned and peer-reviewed.
- Always finalize one mode’s output before switching to the next.
- Use consistent filenames (`spec.md`, `tasks.md`, `spec-feedback.md`) for smooth handoffs.
- Add new roles if emerging responsibilities surface.

---

## 📌 Folder Structure

```

.
├── architect.chatmode.md
├── docwriter.chatmode.md
├── spectester.chatmode.md
├── planner.chatmode.md
├── coder.chatmode.md
├── verifier.chatmode.md
├── infraengineer.chatmode.md
├── README.md  ← (this file)
└── (project artifacts written by each role)

```
