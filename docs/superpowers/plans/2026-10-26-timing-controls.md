# Scan timing controls implementation plan

> For agentic workers: use superpowers:executing-plans inline, then a fresh whole-branch review.

**Goal:** make waits configurable, measure active save steps, preserve guards.
**Architecture:** keep AppleScript idle polling and existing state machine;
add validated external configuration and private sanitized measurements.
**Tech Stack:** AppleScriptObjC, JXA/Foundation, Node and Python test harnesses.
**Spec:** ../specs/2026-10-26-timing-controls-design.md

## Global constraints

- No source/runtime network, real GUI input in tests or private scan fixtures.
- pollIntervalMs integer 100..2000, default 250; migration required.
- Retain all existing reservations, UI guards and timeout behavior.
- Only interval changes preserve transactions; other settings retain idle rearm.
- 128 bounded timing records, enum/numeric data only, outside signed app.
- Never mutate or launch installed helper during source tests/build.
- No public push/release under this implementation instruction.

## Review focus

1. Existing settings missing interval must migrate without disabling or losing a job.
2. Invalid interval values must not corrupt settings or reset a reserved action.
3. Timing data must strip unknown fields and remain bounded; idle must not flood it.
4. Error/timing paths must not retry or dispatch an uncertain action.
5. Native interval selection/formatting and actual idle return must match settings.

### Task 1: runtime configuration and timing storage

Files: src/runtime.js, tests/runtime_test.py.
Interfaces: settings.pollIntervalMs; setSettings patch.pollIntervalMs;
recordTiming(sample with settingsMs/captureMs/policyMs/actionMs/totalMs, actionType)
and getTimings returning timings list.

- [x] Write failing tests for old-settings migration, persistence/range validation,
  interval update during reserved action, sanitized bounded timing data and schema errors.
- [x] Run native runtime suite; verify expected failures.
- [x] Implement validated settings and separate sanitized timing storage without
  changes to core state transitions; preserve state on interval-only updates.
- [x] Run complete suite; require zero failures; commit.

### Task 2: native measurement and interval controls

Files: src/helper.applescript, tests/adapter_test.py, README.md, docs/README.de.md,
CHANGELOG.md, docs/design.md, scripts/build.sh.
Interfaces: idle returns configured seconds; settings menu chooses interval and
shows local timing summary; recordTiming only after active/error polls.

- [x] Write failing native adapter tests for interval selection, timing display,
  timing sample bounds and compiled idle orchestration with I/O substituted.
- [x] Run tests and verify RED; implement native controls and measurement.
- [x] Preserve current capture/action/permission guards; use monotonic durations.
- [x] Run full tests and build/sign; document measured vs unverified speedup.
- [x] Fresh whole-branch review, address material findings with RED/GREEN,
  commit and prepare concrete local update; publication remains separate.
