/**
 * Test suite for .claude/hooks/test-immutability-guard.mjs
 *
 * Strategy: spawn the hook as a child process with spawnSync, feeding JSON to
 * stdin and asserting exit code + stderr content. Each test creates an isolated
 * temp directory containing a `.llm/` subdirectory and runs the hook with cwd
 * set to that temp dir, so no repo files are mutated.
 *
 * Tiers covered:
 *   Tier 1 — Specification tests (acceptance criteria from issue #35)
 *   Tier 2 — Adversarial / boundary tests
 *   Tier 3 — Property-based tests (phase enumeration, path enumeration)
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const HOOK_PATH = path.resolve(
  import.meta.dirname,
  'test-immutability-guard.mjs'
);

/**
 * Create a self-cleaning temp directory that has a `.llm/` sub-directory.
 * Returns { dir, llmDir, cleanup }.
 */
function makeTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tig-test-'));
  const llmDir = path.join(dir, '.llm');
  fs.mkdirSync(llmDir);
  return {
    dir,
    llmDir,
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

/**
 * Write a workflow-state.md with the given phase string.
 * Pass null for phase to write a file with no phase marker.
 * Pass undefined to skip writing the file entirely (simulates missing file).
 */
function writeWorkflowState(llmDir, phase) {
  const filePath = path.join(llmDir, 'workflow-state.md');
  if (phase === undefined) {
    // Don't write the file at all — caller wants it absent.
    return;
  }
  let content = '# Workflow State\n\n## Task\n\n';
  if (phase !== null) {
    content += `**Current Phase:** ${phase}\n`;
  } else {
    // Explicit no-phase-marker case
    content += '## Status\nIn progress\n';
  }
  fs.writeFileSync(filePath, content, 'utf8');
}

/**
 * Run the hook synchronously.
 *
 * @param {object} options
 * @param {string} options.cwd       - Working directory for the hook process
 * @param {object} options.input     - Object to serialize as stdin JSON
 * @returns {{ exitCode: number, stderr: string }}
 */
function runHook({ cwd, input }) {
  const result = spawnSync(process.execPath, [HOOK_PATH], {
    input: JSON.stringify(input),
    cwd,
    encoding: 'utf8',
    timeout: 5000,
  });

  return {
    exitCode: result.status ?? -1,
    stderr: result.stderr ?? '',
  };
}

// ---------------------------------------------------------------------------
// Convenience builders for common input shapes
// ---------------------------------------------------------------------------

function makeInput(toolName, filePath) {
  const tool_input = filePath !== undefined ? { file_path: filePath } : {};
  return { tool_name: toolName, tool_input };
}

// ---------------------------------------------------------------------------
// TIER 1 — Specification Tests
// (Direct 1:1 mapping to acceptance criteria)
// ---------------------------------------------------------------------------

describe('Tier 1 — Specification Tests', () => {
  // Assertion 1: Hook exits 0 when tool is NOT Write, Edit, or NotebookEdit
  test('allows Bash tool regardless of path and phase', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Bash', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Bash tool must always be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows Read tool regardless of path and phase', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Read', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Read tool must always be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows ListFiles tool regardless of path and phase', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('ListFiles', 'tests/'),
      });
      assert.equal(exitCode, 0, 'ListFiles tool must always be allowed');
    } finally {
      cleanup();
    }
  });

  // Assertion 2: Hook exits 0 when tool is Write/Edit/NotebookEdit but path does not match test pattern
  test('allows Write tool when path does not match any test pattern', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'src/main.js'),
      });
      assert.equal(exitCode, 0, 'Write to non-test path must be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows Edit tool when path does not match any test pattern', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Edit', 'lib/utils.ts'),
      });
      assert.equal(exitCode, 0, 'Edit to non-test path must be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows NotebookEdit tool when path does not match any test pattern', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('NotebookEdit', 'notebooks/analysis.ipynb'),
      });
      assert.equal(exitCode, 0, 'NotebookEdit to non-test path must be allowed');
    } finally {
      cleanup();
    }
  });

  // Assertion 3: Hook exits 2 when tool is Write/Edit/NotebookEdit AND path matches test pattern AND phase is GREEN
  test('blocks Write to test-pattern path when phase is GREEN', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 2, 'Write to test path in GREEN must be blocked');
    } finally {
      cleanup();
    }
  });

  test('blocks Edit to test-pattern path when phase is GREEN', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Edit', 'src/foo.test.ts'),
      });
      assert.equal(exitCode, 2, 'Edit to test path in GREEN must be blocked');
    } finally {
      cleanup();
    }
  });

  test('blocks NotebookEdit to test-pattern path when phase is GREEN', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('NotebookEdit', 'tests/notebook.test.js'),
      });
      assert.equal(exitCode, 2, 'NotebookEdit to test path in GREEN must be blocked');
    } finally {
      cleanup();
    }
  });

  // Assertion 4: Hook exits 2 when tool is Write/Edit/NotebookEdit AND path matches test pattern AND phase is REFACTOR
  test('blocks Write to test-pattern path when phase is REFACTOR', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'REFACTOR');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 2, 'Write to test path in REFACTOR must be blocked');
    } finally {
      cleanup();
    }
  });

  test('blocks Edit to test-pattern path when phase is REFACTOR', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'REFACTOR');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Edit', 'src/foo.spec.ts'),
      });
      assert.equal(exitCode, 2, 'Edit to test path in REFACTOR must be blocked');
    } finally {
      cleanup();
    }
  });

  // Assertion 5: Hook exits 0 when phase is RED (test writing allowed in RED)
  test('allows Write to test-pattern path when phase is RED', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'RED');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Write to test path in RED must be allowed');
    } finally {
      cleanup();
    }
  });

  // Assertion 6: Hook exits 0 when workflow-state.md does not exist (fail-safe)
  test('allows when workflow-state.md does not exist', () => {
    const { dir, cleanup } = makeTempDir();
    // Note: we created the temp dir but did NOT write workflow-state.md
    try {
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Missing workflow-state.md must be fail-safe (allow)');
    } finally {
      cleanup();
    }
  });

  // Assertion 7: Hook exits 0 when workflow-state.md exists but has no phase marker
  test('allows when workflow-state.md exists but contains no phase marker', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, null); // null = write file but no phase line
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Missing phase marker must be fail-safe (allow)');
    } finally {
      cleanup();
    }
  });

  // Assertion 8: Error message on exit 2 includes the blocked file path
  test('stderr on block includes the blocked file path', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    const blockedPath = 'tests/important.test.ts';
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode, stderr } = runHook({
        cwd: dir,
        input: makeInput('Write', blockedPath),
      });
      assert.equal(exitCode, 2);
      assert.ok(
        stderr.includes(blockedPath),
        `stderr must include the blocked path "${blockedPath}" but got: ${stderr}`
      );
    } finally {
      cleanup();
    }
  });

  // Assertion 8 (continued): Error message on exit 2 includes the current phase
  test('stderr on block includes the current phase name', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode, stderr } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 2);
      assert.ok(
        stderr.includes('GREEN'),
        `stderr must include "GREEN" but got: ${stderr}`
      );
    } finally {
      cleanup();
    }
  });

  test('stderr on REFACTOR block includes the phase REFACTOR', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'REFACTOR');
      const { exitCode, stderr } = runHook({
        cwd: dir,
        input: makeInput('Edit', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 2);
      assert.ok(
        stderr.includes('REFACTOR'),
        `stderr must include "REFACTOR" but got: ${stderr}`
      );
    } finally {
      cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// TIER 2 — Adversarial / Boundary Tests
// ---------------------------------------------------------------------------

describe('Tier 2 — Boundary: All seven test-path patterns blocked in GREEN', () => {
  const patterns = [
    { label: 'tests/ directory prefix (plural)',      path: 'tests/some_module.rs' },
    { label: 'test/ directory prefix (singular)',     path: 'test/helpers.ts' },
    { label: '.test.ts extension',                    path: 'src/auth.test.ts' },
    { label: '.test.js extension',                    path: 'src/auth.test.js' },
    { label: '.test.tsx extension',                   path: 'src/auth.test.tsx' },
    { label: '.test.jsx extension',                   path: 'src/auth.test.jsx' },
    { label: '.spec.ts extension',                    path: 'src/auth.spec.ts' },
    { label: '.spec.js extension',                    path: 'src/auth.spec.js' },
    { label: '.spec.tsx extension',                   path: 'src/auth.spec.tsx' },
    { label: '.spec.jsx extension',                   path: 'src/auth.spec.jsx' },
    { label: 'C# Tests.cs suffix (plural)',           path: 'MyClassTests.cs' },
    { label: 'C# Test.cs suffix (singular)',          path: 'MyClassTest.cs' },
    { label: 'Rust integration test in tests/ dir',   path: 'tests/integration_test.rs' },
    { label: 'Go _test.go suffix',                    path: 'something_test.go' },
    { label: 'Python test_ prefix',                   path: 'test_something.py' },
    { label: 'Nested tests/ directory',               path: 'project/tests/unit.test.js' },
    { label: 'Nested test/ directory',                path: 'project/test/helpers.ts' },
  ];

  for (const { label, path: filePath } of patterns) {
    test(`blocks Write to "${label}" when phase is GREEN`, () => {
      const { dir, llmDir, cleanup } = makeTempDir();
      try {
        writeWorkflowState(llmDir, 'GREEN');
        const { exitCode } = runHook({
          cwd: dir,
          input: makeInput('Write', filePath),
        });
        assert.equal(exitCode, 2, `Write to "${filePath}" in GREEN must be blocked`);
      } finally {
        cleanup();
      }
    });
  }
});

describe('Tier 2 — Boundary: Non-test paths allowed in GREEN', () => {
  const nonTestPaths = [
    'src/main.js',
    'lib/utils.ts',
    'index.mjs',
    'src/contest.js',          // contains "test" but not as pattern
    'docs/atestament.md',      // contains "test" in the middle of a word
    'src/tests.js',            // the word "tests" as a filename stem, no directory
    'src/myspec.ts',           // contains "spec" but not as .spec.ts
    'notebooks/analysis.ipynb',
    'README.md',
    'package.json',
    'Cargo.toml',
    'go.mod',
  ];

  for (const filePath of nonTestPaths) {
    test(`allows Write to non-test path "${filePath}" in GREEN`, () => {
      const { dir, llmDir, cleanup } = makeTempDir();
      try {
        writeWorkflowState(llmDir, 'GREEN');
        const { exitCode } = runHook({
          cwd: dir,
          input: makeInput('Write', filePath),
        });
        assert.equal(exitCode, 0, `Write to "${filePath}" must be allowed even in GREEN`);
      } finally {
        cleanup();
      }
    });
  }
});

describe('Tier 2 — Adversarial: Phase case sensitivity', () => {
  test('does not block when phase is "green" (lowercase) — only uppercase GREEN triggers block', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'green');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Lowercase "green" must not trigger block');
    } finally {
      cleanup();
    }
  });

  test('does not block when phase is "refactor" (lowercase)', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'refactor');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Lowercase "refactor" must not trigger block');
    } finally {
      cleanup();
    }
  });

  test('does not block when phase is "Green" (mixed case)', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'Green');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Mixed case "Green" must not trigger block');
    } finally {
      cleanup();
    }
  });
});

describe('Tier 2 — Adversarial: Non-blocking phases', () => {
  const allowedPhases = ['RED', 'AUDIT', 'DONE', 'PLAN', 'DESIGN', 'COMPLETE'];

  for (const phase of allowedPhases) {
    test(`allows Write to test-pattern path when phase is "${phase}"`, () => {
      const { dir, llmDir, cleanup } = makeTempDir();
      try {
        writeWorkflowState(llmDir, phase);
        const { exitCode } = runHook({
          cwd: dir,
          input: makeInput('Write', 'tests/foo.test.js'),
        });
        assert.equal(exitCode, 0, `Phase "${phase}" must not block`);
      } finally {
        cleanup();
      }
    });
  }
});

describe('Tier 2 — Adversarial: Missing or malformed tool_input', () => {
  test('allows when tool_input has no file_path key', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: { tool_name: 'Write', tool_input: {} },
      });
      assert.equal(exitCode, 0, 'Missing file_path key must be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows when file_path is empty string', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', ''),
      });
      assert.equal(exitCode, 0, 'Empty file_path must be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows when tool_input is absent entirely', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: { tool_name: 'Write' },
      });
      assert.equal(exitCode, 0, 'Missing tool_input must be allowed (no crash)');
    } finally {
      cleanup();
    }
  });

  test('allows when stdin is malformed JSON', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const result = spawnSync(process.execPath, [HOOK_PATH], {
        input: 'NOT_VALID_JSON{{{',
        cwd: dir,
        encoding: 'utf8',
        timeout: 5000,
      });
      const exitCode = result.status ?? -1;
      assert.equal(exitCode, 0, 'Malformed JSON must be fail-safe (allow), not crash');
    } finally {
      cleanup();
    }
  });

  test('allows when stdin is empty', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const result = spawnSync(process.execPath, [HOOK_PATH], {
        input: '',
        cwd: dir,
        encoding: 'utf8',
        timeout: 5000,
      });
      const exitCode = result.status ?? -1;
      assert.equal(exitCode, 0, 'Empty stdin must be fail-safe (allow)');
    } finally {
      cleanup();
    }
  });
});

describe('Tier 2 — Adversarial: Phase line edge cases in workflow-state.md', () => {
  test('allows when phase line value is blank: "**Current Phase:** "', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      const statePath = path.join(llmDir, 'workflow-state.md');
      fs.writeFileSync(statePath, '# Workflow State\n**Current Phase:** \n', 'utf8');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Blank phase value must be allowed');
    } finally {
      cleanup();
    }
  });

  test('allows when phase line has trailing whitespace: "**Current Phase:** GREEN  "', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      // The hook should still detect GREEN even with trailing whitespace
      const statePath = path.join(llmDir, 'workflow-state.md');
      fs.writeFileSync(statePath, '# Workflow State\n**Current Phase:** GREEN  \n', 'utf8');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      // Trailing whitespace — implementation should trim. Block is expected.
      assert.equal(exitCode, 2, 'Trailing whitespace after GREEN should still trigger block');
    } finally {
      cleanup();
    }
  });

  test('allows when .llm directory exists but workflow-state.md is absent', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      // llmDir exists but no file written
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, '.llm dir present but file absent must be fail-safe');
    } finally {
      cleanup();
    }
  });

  test('allows when workflow-state.md is empty', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      fs.writeFileSync(path.join(llmDir, 'workflow-state.md'), '', 'utf8');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0, 'Empty workflow-state.md must be fail-safe');
    } finally {
      cleanup();
    }
  });
});

describe('Tier 2 — Adversarial: Exit code precision', () => {
  test('exit code is exactly 2 when blocking (not 1 or 3)', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 2);
      assert.notEqual(exitCode, 1);
      assert.notEqual(exitCode, 3);
    } finally {
      cleanup();
    }
  });

  test('exit code is exactly 0 when allowing (not 1 or 2)', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'RED');
      const { exitCode } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      assert.equal(exitCode, 0);
      assert.notEqual(exitCode, 1);
      assert.notEqual(exitCode, 2);
    } finally {
      cleanup();
    }
  });
});

describe('Tier 2 — Adversarial: Stub-killing tests', () => {
  // These tests are designed so that no single hardcoded return value can satisfy all.

  test('same path is blocked in GREEN but allowed in RED — rules out hardcoded exit 0', () => {
    const testPath = 'tests/critical.test.ts';

    const { dir: dirGreen, llmDir: llmGreen, cleanup: cleanGreen } = makeTempDir();
    const { dir: dirRed, llmDir: llmRed, cleanup: cleanRed } = makeTempDir();
    try {
      writeWorkflowState(llmGreen, 'GREEN');
      writeWorkflowState(llmRed, 'RED');

      const { exitCode: codeGreen } = runHook({ cwd: dirGreen, input: makeInput('Write', testPath) });
      const { exitCode: codeRed } = runHook({ cwd: dirRed, input: makeInput('Write', testPath) });

      assert.equal(codeGreen, 2, 'GREEN must block');
      assert.equal(codeRed, 0, 'RED must allow');
    } finally {
      cleanGreen();
      cleanRed();
    }
  });

  test('same phase GREEN blocks test path but allows non-test path — rules out hardcoded exit 2', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');

      const { exitCode: codeTest } = runHook({ cwd: dir, input: makeInput('Write', 'tests/foo.test.js') });
      const { exitCode: codeNonTest } = runHook({ cwd: dir, input: makeInput('Write', 'src/main.js') });

      assert.equal(codeTest, 2, 'Test path in GREEN must block');
      assert.equal(codeNonTest, 0, 'Non-test path in GREEN must allow');
    } finally {
      cleanup();
    }
  });

  test('different tools have different outcomes for same path and phase', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const filePath = 'tests/foo.test.js';

      const { exitCode: writeCode } = runHook({ cwd: dir, input: makeInput('Write', filePath) });
      const { exitCode: bashCode } = runHook({ cwd: dir, input: makeInput('Bash', filePath) });

      assert.equal(writeCode, 2, 'Write must block');
      assert.equal(bashCode, 0, 'Bash must allow');
    } finally {
      cleanup();
    }
  });

  test('REFACTOR blocks but AUDIT does not — rules out blocking on any non-RED phase', () => {
    const testPath = 'src/auth.spec.ts';

    const { dir: dirRefactor, llmDir: llmRefactor, cleanup: cleanRefactor } = makeTempDir();
    const { dir: dirAudit, llmDir: llmAudit, cleanup: cleanAudit } = makeTempDir();
    try {
      writeWorkflowState(llmRefactor, 'REFACTOR');
      writeWorkflowState(llmAudit, 'AUDIT');

      const { exitCode: codeRefactor } = runHook({ cwd: dirRefactor, input: makeInput('Edit', testPath) });
      const { exitCode: codeAudit } = runHook({ cwd: dirAudit, input: makeInput('Edit', testPath) });

      assert.equal(codeRefactor, 2, 'REFACTOR must block');
      assert.equal(codeAudit, 0, 'AUDIT must allow');
    } finally {
      cleanRefactor();
      cleanAudit();
    }
  });
});

describe('Tier 2 — Adversarial: Stderr content does not leak internal paths', () => {
  test('stderr does not contain Node.js stack trace on block', () => {
    const { dir, llmDir, cleanup } = makeTempDir();
    try {
      writeWorkflowState(llmDir, 'GREEN');
      const { stderr } = runHook({
        cwd: dir,
        input: makeInput('Write', 'tests/foo.test.js'),
      });
      // Stack traces contain "at " prefixed lines
      const hasStackTrace = /^\s+at\s+/m.test(stderr);
      assert.ok(!hasStackTrace, `stderr must not contain a stack trace. Got: ${stderr}`);
    } finally {
      cleanup();
    }
  });
});

// ---------------------------------------------------------------------------
// TIER 3 — Property-Based Tests
// (Enumerate over generated inputs to verify invariants hold universally)
// ---------------------------------------------------------------------------

describe('Tier 3 — Property: Non-blocking phases never block test-pattern paths', () => {
  // Exhaustive enumeration of all phases that must NOT block.
  // Any phase not in the blocking set {GREEN, REFACTOR} must be a pass-through.
  const nonBlockingPhases = [
    'RED', 'AUDIT', 'DONE', 'PLAN', 'DESIGN', 'REVIEW',
    'COMPLETE', 'INIT', 'DEPLOY', 'VALIDATE',
    // Partial matches that should NOT trigger (substring attacks)
    'NOT-GREEN', 'PRE-GREEN', 'GREEN-DONE',
    'PRE-REFACTOR', 'REFACTOR-DONE',
  ];

  const testPatternPaths = [
    'tests/foo.test.ts',
    'src/bar.spec.js',
    'MyServiceTests.cs',
    'something_test.go',
    'test_module.py',
  ];

  for (const phase of nonBlockingPhases) {
    for (const filePath of testPatternPaths) {
      test(`phase "${phase}" allows Write to "${filePath}"`, () => {
        const { dir, llmDir, cleanup } = makeTempDir();
        try {
          writeWorkflowState(llmDir, phase);
          const { exitCode } = runHook({
            cwd: dir,
            input: makeInput('Write', filePath),
          });
          assert.equal(
            exitCode,
            0,
            `Phase "${phase}" must not block "${filePath}" — only GREEN and REFACTOR block`
          );
        } finally {
          cleanup();
        }
      });
    }
  }
});

describe('Tier 3 — Property: Non-test paths always allowed in GREEN regardless of tool', () => {
  const tools = ['Write', 'Edit', 'NotebookEdit'];
  const nonTestPaths = [
    'src/index.ts',
    'lib/helpers.js',
    'Cargo.toml',
    'go.mod',
    'pyproject.toml',
    '.claude/settings.json',
    'src/hooks/my-hook.mjs',
    // Tricky: contains the word "test" but is not a test file
    'src/latestFeature.ts',
    'docs/attestation.md',
    'src/protest.js',
  ];

  for (const tool of tools) {
    for (const filePath of nonTestPaths) {
      test(`"${tool}" to non-test path "${filePath}" always allowed in GREEN`, () => {
        const { dir, llmDir, cleanup } = makeTempDir();
        try {
          writeWorkflowState(llmDir, 'GREEN');
          const { exitCode } = runHook({
            cwd: dir,
            input: makeInput(tool, filePath),
          });
          assert.equal(
            exitCode,
            0,
            `"${tool}" to "${filePath}" must always be allowed in GREEN`
          );
        } finally {
          cleanup();
        }
      });
    }
  }
});

describe('Tier 3 — Property: Hook never crashes on arbitrary JSON shapes', () => {
  const arbitraryInputs = [
    null,
    42,
    'string',
    [],
    {},
    { tool_name: null },
    { tool_name: 'Write', tool_input: null },
    { tool_name: 'Write', tool_input: { file_path: null } },
    { tool_name: 'Write', tool_input: { file_path: 12345 } },
    { tool_name: 'Write', tool_input: { file_path: ['a', 'b'] } },
    { tool_name: '', tool_input: { file_path: 'tests/foo.test.js' } },
    { extra_field: true, tool_name: 'Write', tool_input: { file_path: 'tests/foo.test.js' } },
  ];

  for (const [idx, inputValue] of arbitraryInputs.entries()) {
    test(`hook exits 0 (no crash) for arbitrary input shape #${idx}`, () => {
      const { dir, llmDir, cleanup } = makeTempDir();
      try {
        writeWorkflowState(llmDir, 'GREEN');
        const result = spawnSync(process.execPath, [HOOK_PATH], {
          input: JSON.stringify(inputValue),
          cwd: dir,
          encoding: 'utf8',
          timeout: 5000,
        });
        const exitCode = result.status ?? -1;
        // The hook must either allow (0) or block (2) — never crash to a different code
        assert.ok(
          exitCode === 0 || exitCode === 2,
          `Hook must exit 0 or 2, not crash with code ${exitCode}. Input: ${JSON.stringify(inputValue)}`
        );
      } finally {
        cleanup();
      }
    });
  }
});

describe('Tier 3 — Property: All three blocking tools are symmetric for same path and phase', () => {
  // Write, Edit, and NotebookEdit must behave identically given the same path and phase.
  const blockingPhases = ['GREEN', 'REFACTOR'];
  const testPatternPaths = [
    'tests/module.test.ts',
    'src/service.spec.js',
  ];

  for (const phase of blockingPhases) {
    for (const filePath of testPatternPaths) {
      test(`Write, Edit, and NotebookEdit all block "${filePath}" in ${phase}`, () => {
        const { dir, llmDir, cleanup } = makeTempDir();
        try {
          writeWorkflowState(llmDir, phase);
          const writeResult = runHook({ cwd: dir, input: makeInput('Write', filePath) });
          const editResult = runHook({ cwd: dir, input: makeInput('Edit', filePath) });
          const notebookResult = runHook({ cwd: dir, input: makeInput('NotebookEdit', filePath) });

          assert.equal(writeResult.exitCode, 2, `Write must block "${filePath}" in ${phase}`);
          assert.equal(editResult.exitCode, 2, `Edit must block "${filePath}" in ${phase}`);
          assert.equal(notebookResult.exitCode, 2, `NotebookEdit must block "${filePath}" in ${phase}`);
        } finally {
          cleanup();
        }
      });
    }
  }
});
