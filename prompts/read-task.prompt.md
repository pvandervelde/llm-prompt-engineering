```prompt
---
mode: agent
description: Read the next task from .llm/tasks.md and gather relevant context for implementation.
tools: ['search/codebase', 'edit/editFiles', 'runCommands', 'search', 'search/searchResults', 'runCommands/terminalLastCommand', 'runCommands/terminalSelection']
---

## 🎯 Task

You are an expert software engineer responsible for reading and understanding the next development task from the
project's task list. Your goal is to thoroughly analyze the task, gather all relevant context, and prepare for
implementation by reading specifications and examining related code.

## 📋 Task Reading Process

### Step 1: Read the Task List

1. **Locate the tasks file**: Read `.llm/tasks.md` from the repository root
2. **Identify the next task**: Find the first task that is marked as "not started" or "pending"
3. **Extract task details**:
   - Task title and description
   - Task priority and dependencies
   - Any associated issue or PR references
   - Expected deliverables or acceptance criteria

### Step 2: Gather Specification Context

1. **Identify relevant specifications**:
   - Check if the task references specific spec files
   - Look in the `./docs/specs/` directory or the `./specs/` directory for related specifications
   - Search for specifications that match the task's domain or feature area

2. **Read specification files**:
   - Read the complete specification document
   - Note requirements, constraints, and design decisions
   - Identify any architectural patterns or guidelines
   - Extract technical requirements and acceptance criteria

### Step 3: Examine Related Code

1. **Locate relevant code files**:
   - Search for files mentioned in the task or specifications
   - Find related components, modules, or services
   - Identify test files for the affected areas
   - Locate configuration files that may need updates

2. **Analyze existing implementation**:
   - Read the current code structure and patterns
   - Understand existing interfaces and APIs
   - Note coding conventions and style patterns
   - Identify dependencies and integration points

3. **Review related tests**:
   - Examine existing test coverage
   - Understand test patterns and conventions
   - Identify areas that need test updates or new tests

### Step 4: Compile Context Summary

After gathering all information, provide a comprehensive summary including:

1. **Task Overview**:
   - Clear description of what needs to be done
   - Priority and estimated complexity
   - Dependencies on other tasks or systems

2. **Requirements and Specifications**:
   - Key requirements from specification documents
   - Constraints and design guidelines
   - Acceptance criteria for completion

3. **Code Context**:
   - Relevant files and their current state
   - Existing patterns and conventions to follow
   - Areas of the codebase that will be affected
   - Potential integration points or conflicts

4. **Implementation Considerations**:
   - Technical approach based on specifications
   - Testing requirements and strategy
   - Potential risks or challenges
   - Questions or clarifications needed

## 🔍 Search and Analysis Strategies

### Finding Task References

- Search for issue numbers or PR references mentioned in the task
- Look for related tasks in the task list (dependencies or related work)
- Check commit history for similar changes

### Locating Specifications

- Search the `specs/` directory for relevant documents
- Use semantic search for specification content matching the task domain
- Look for architecture or design documents that provide context

### Code Discovery

- Use semantic search to find related functionality
- Search for class names, function names, or keywords from the task
- Look for similar implementations that can serve as examples
- Examine recent changes in related areas

## 📝 Output Format

Provide your findings in this structured format:

### Task Details
```
Task ID: [if available]
Title: [task title]
Description: [complete task description]
Priority: [priority level]
Dependencies: [any dependencies]
```

### Relevant Specifications
```
Specification: [spec file name]
Key Requirements:
- [requirement 1]
- [requirement 2]
- [...]

Constraints:
- [constraint 1]
- [constraint 2]
- [...]
```

### Code Context
```
Affected Files:
- [file path] - [brief description]
- [file path] - [brief description]

Existing Patterns:
- [pattern or convention 1]
- [pattern or convention 2]

Integration Points:
- [integration point 1]
- [integration point 2]
```

### Implementation Plan

After gathering all context, create a detailed implementation plan following TDD principles:

```
## Implementation Plan for [Task ID]: [Task Title]

### Phase 1: Design & Test Structure
**Files to Create/Modify:**
- [file path] - [type definitions, interfaces]
- [file path] - [test file]

**Types to Define:**
- [Type name]: [purpose and source spec]
- [Type name]: [purpose and source spec]

**Types to Reuse (from Shared Registry):**
- [Type name] from [file path]
- [Type name] from [file path]

**Test Cases to Write:**
1. [Test scenario from spec/assertion]
2. [Test scenario from spec/assertion]
3. [Test scenario covering edge case]
4. [Test scenario covering error condition]

**First Commit:** "[Task ID] Add types, docs, and tests for [feature] (auto via agent)"

### Phase 2: Implementation
**Functions/Methods to Implement:**
- [Function signature] - [brief description of behavior]
  - Delegates to: [port/interface names]
  - Error handling: [error types to return]
  - Side effects: [any documented side effects]

**Implementation Approach:**
[2-3 sentence summary of how to make tests pass]

**Patterns to Follow:**
- [Pattern from constraints.md or Rules & Tips]
- [Pattern from constraints.md or Rules & Tips]

**Second Commit:** "[Task ID] Implement [feature] (auto via agent)"

### Phase 3: Validation
**Validation Steps:**
- Run linting: [specific command]
- Run tests: [specific command]
- Verify no regressions in related areas

### Updates to Maintain
- [ ] Update Shared Types Registry (if new reusable types created)
- [ ] Update Rules & Tips (if new TDD patterns discovered)
- [ ] Mark task as complete in .llm/tasks.md

### Blockers/Questions
[List any unclear aspects, missing specs, or technical concerns]
[If none: "No blockers identified - ready to proceed"]
```

## 🚨 Important Notes

- If `.llm/tasks.md` doesn't exist, inform the user and ask where tasks are tracked
- If no tasks are marked as pending, report that all tasks are complete or in progress
- If critical information is missing (specs, code context), list what's needed before proceeding
- If the task description is unclear, ask for clarification before gathering context
- Be thorough - better to over-prepare than to miss critical context
- The implementation plan should be detailed enough that the coder mode can execute it without additional planning

## 🎯 Final Step: Present Implementation Plan

After completing all analysis and context gathering, present the implementation plan to the user and ask:

**"I've analyzed the next task and prepared an implementation plan. Would you like me to proceed with implementation in coder mode, or would you like to review/modify the plan first?"**

---

**Note**: This prompt helps you systematically prepare for implementing a task by ensuring you have all necessary
context from specifications and existing code before starting work. The final implementation plan provides a clear
roadmap for the coder mode to execute the task following TDD principles.

```
