#!/usr/bin/env node
/**
 * PreToolUse hook: blocks Write/Edit/NotebookEdit to test-file paths while the
 * pipeline's workflow state reports Current Phase GREEN or REFACTOR.
 *
 * Protocol: reads a JSON tool-call payload from stdin, exits 0 to allow the
 * call through or 2 to block it (Claude Code shows stderr to the agent on
 * exit 2). Any failure to read state, or state that doesn't say GREEN/REFACTOR,
 * is fail-safe and allows the call — this hook only ever blocks on a
 * positive match.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

const STATE_PATH = path.join('.llm', 'workflow-state.md');
const BLOCKED_TOOLS = new Set(['Write', 'Edit', 'NotebookEdit']);
const BLOCKING_PHASES = new Set(['GREEN', 'REFACTOR']);

const TEST_GLOBS = [
  /(^|\/)tests?\//, // tests/, test/
  /\.test\.[jt]sx?$/, // TypeScript / JavaScript
  /\.spec\.[jt]sx?$/,
  /Tests?\.cs$/, // C# xUnit / NUnit convention
  /(^|\/)tests\/.*\.rs$/, // Rust integration tests
  /_test\.go$/, // Go
  /(^|\/)test_.*\.py$/, // Python
];

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function parseInput(raw) {
  try {
    const value = JSON.parse(raw);
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch {
    return {};
  }
}

function isTestPath(filePath) {
  return typeof filePath === 'string' && TEST_GLOBS.some((re) => re.test(filePath));
}

function currentPhase() {
  let content;
  try {
    content = readFileSync(STATE_PATH, 'utf8');
  } catch {
    return ''; // no state file → not in a pipeline run
  }
  const match = content.match(/\*\*Current Phase:\*\*\s*(.*)/);
  return match ? match[1].trim() : '';
}

function main() {
  const input = parseInput(readStdin());
  const tool = input.tool_name;
  const filePath = input.tool_input && typeof input.tool_input === 'object'
    ? input.tool_input.file_path
    : undefined;

  if (!BLOCKED_TOOLS.has(tool) || !isTestPath(filePath)) {
    process.exit(0);
  }

  const phase = currentPhase();
  if (!BLOCKING_PHASES.has(phase)) {
    process.exit(0);
  }

  console.error(
    `BLOCKED: ${filePath} is a test file and the pipeline is in ${phase}. ` +
      `Tests are frozen after the RED commit. If a test is wrong, report it to the ` +
      `Tech Lead as a spec gap — do not edit it.`
  );
  process.exit(2);
}

main();
