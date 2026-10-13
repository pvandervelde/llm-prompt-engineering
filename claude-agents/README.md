# Agent Pipeline Graph

This graph is generated from the `## Collaboration` block in each agent file. If you add,
remove, or reorder an agent, update that agent's Collaboration block (and the block of
every agent it now hands off to or receives from) and update this diagram to match — the
two must never drift apart.

The Tech Lead and Infrastructure Lead are the only agents that may invoke another agent
directly (via the `Task` tool). Every edge below is a logical artifact handoff, not a
literal subagent call made by the producing agent itself.

```mermaid
flowchart TD
    subgraph Software Pipeline
        Architect["Software Architect"]
        UX["UX Designer"]
        IFace["Interface Designer"]
        DesignRev["Design Reviewer"]
        Doc["Doc Writer"]
        Plan["Task Planner"]
        SpecRev["Spec Reviewer"]
        TechLead["Tech Lead (orchestrator)"]
        Tester["Tester"]
        Coder["Coder"]
        Refactor["Refactor"]
        QA["QA Engineer"]
        Sec["Security Reviewer"]
        Verifier["Verifier"]

        Architect --> IFace
        Architect --> UX
        UX --> IFace
        IFace --> DesignRev
        DesignRev -->|CLEAR| Doc
        DesignRev -->|CLEAR| Plan
        DesignRev -.->|BLOCKED: routes to owning agent| Architect
        Doc --> Plan
        Plan --> SpecRev
        SpecRev -->|CLEAR| TechLead
        SpecRev -.->|BLOCKED: routes to owning agent| Architect
        TechLead --> Tester --> Coder --> Refactor
        Refactor --> QA
        Refactor --> Sec
        QA --> Doc2["Doc Writer (DOCUMENT mode)"]
        Sec --> Doc2
        Doc2 --> Verifier
        Verifier -->|PASS| PR1[("Open PR")]
    end

    subgraph Infrastructure Pipeline
        InfraArch["Infrastructure Architect"]
        InfraDes["Infrastructure Designer"]
        InfraLead["Infrastructure Lead (orchestrator)"]
        InfraEng["Infrastructure Engineer"]
        Sec2["Security Reviewer"]
        Verifier2["Verifier"]

        InfraArch --> InfraDes --> Plan
        Plan -->|no Spec Reviewer gate| InfraLead
        InfraLead --> InfraEng --> Sec2 --> Verifier2
        Verifier2 -->|PASS| PR2[("Open PR")]
    end
```

## Notes

- **Doc Writer** appears twice in the diagram above (DRAFT mode, between Interface Designer
  and Task Planner; DOCUMENT mode, after AUDIT + SECURITY) because it is one file operating
  in two explicit modes — see `docwriter.md`.
- **Design Reviewer** is the pre-code adversarial gate (see #51): it runs before any test or
  code exists, checking the whole design bundle (architecture, responsibilities,
  assertions, vocabulary, constraints, and the interface spec) for defects that would
  otherwise only surface once the Verifier runs at the very end of the pipeline.
- **QA Engineer** and **Security Reviewer** run in parallel in the software pipeline (both
  gate on the same Refactor output); Security Reviewer is reused standalone in the
  infrastructure pipeline, where there is no QA Engineer phase.
- **Spec Reviewer** only gates the software pipeline. The infrastructure pipeline has no
  pre-implementation spec-review gate (see `infra-lead.md` / `planner.md` Collaboration
  blocks).
