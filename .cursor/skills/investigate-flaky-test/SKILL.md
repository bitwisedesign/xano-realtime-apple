---
name: investigate-flaky-test
description: >-
  Investigate and fix a flaky (intermittently failing) Swift test in this
  iOS + macOS SDK package. Use when the user reports a test that fails
  intermittently in CI or locally, asks to investigate/fix/stabilize a flaky,
  non-deterministic, or racy test, or mentions a test that "fails ~1 per PR".
  Enforces prove-first: reproduce the flake before changing anything, fix the
  production code (not the assertion), then prove the fix over many repeated
  runs.
---

# Investigate & Fix a Flaky Test

Swift Testing has **no native repeat-count flag**. Prove flakiness with a temporary
parameterized `@Test(arguments: 0..<N)` — the cases run in parallel, which amplifies
scheduler races and is far faster and more reliable than a shell loop.

Do **not** skip straight to a fix. Reproduce first, fix the code, then re-prove.

## Workflow

```markdown
- [ ] 1. Reproduce the flake on the CURRENT code (baseline failure rate)
- [ ] 2. Diagnose the root cause
- [ ] 3. Fix the production code (not the expectation)
- [ ] 4. Prove the fix: revert → flaky, re-apply → 100% green over several passes
- [ ] 5. Remove the temporary stress test; keep a permanent regression test
```

### 1. Reproduce first

Add a temporary stress test next to the flaky one that repeats the exact failing
scenario as parameterized cases. Build a fresh subject per case (no shared state).

```swift
@Test("STRESS <scenario>", arguments: 0 ..< 100)
func stressScenario(iteration: Int) async throws {
    // ... identical setup + action as the flaky test ...
    #expect(result == expected, "iteration \(iteration) got \(result)")
}
```

Run it and record the baseline failure rate:

```bash
swift test --filter <SuiteOrTestName> 2>&1 | tail -40
```

- If it fails some fraction of the 100 cases, you have a reproduction. Note the rate.
- If it stays green: raise `N`, add an inner loop per case, or match the real
  concurrency (e.g. `async let` racing two calls). Only if in-process repetition
  truly cannot reproduce, fall back to a shell loop of one process per run:
  `for i in $(seq 100); do swift test --filter <name> || echo "FAIL $i"; done`
  (slower; each single-shot trial has lower odds — this mirrors CI's low per-run rate).

### 2. Diagnose

Common flake sources in this package, most likely first:

- **Actor reentrancy (check-then-act across `await`).** A "find-or-insert" / guard
  that reads state, then `await`s another call before writing, is **not atomic**:
  an `await` — *even to a method on the same actor* — is a suspension point where a
  concurrent task interleaves and both branches insert/act. This is the canonical
  flake here. Fix by making the read+write a single synchronous region on the actor
  (extract a non-`async` helper; call it with no `await` between check and mutate).
- **Time-based waits.** `Task.sleep` to "wait for" state is banned by `testing.mdc`
  and is inherently racy — replace with deterministic waits (continuations/async
  results), not longer sleeps.
- **Ordering assumptions** on dictionary iteration / unsorted snapshots.
- **Shared mutable static/global state** across parallel test cases.

### 3. Fix the code, not the test

Assume the implementation (or a test double that mis-models production) is
wrong. Do not "stabilize" by loosening the assertion, adding sleeps, or
serializing the test to hide a real production race. If the production type
already serializes and only the in-memory test double races, fix the double
to match that guarantee.

### 4. Prove the fix

Show the stress test fails on the old code and passes on the new code. Preserve
your fix, revert to the committed version, run, then restore:

```bash
cp <path/to/File.swift> /tmp/fixed.swift
git checkout HEAD -- <path/to/File.swift>      # buggy baseline
swift test --filter <name> 2>&1 | tail -40     # expect failures
cp /tmp/fixed.swift <path/to/File.swift>       # restore fix
swift test --filter <name> 2>&1 | tail -15     # expect all green
```

Then run the fixed stress a few more passes to be confident:

```bash
for i in 1 2 3; do swift test --filter stressScenario 2>&1 | tail -2; done
```

Never use `git add`/`git stash` on the user's behalf (see `git-commands.mdc`);
`git checkout HEAD -- <file>` only touches that one path in the working tree.

### 5. Clean up

Remove the temporary `STRESS` test. Keep (or strengthen) the original
deterministic regression test so the fix stays covered. After editing any test
file, run SwiftLint per `swiftlint.mdc`:

```bash
swiftlint --fix --no-cache <abs/path/to/EditedTest.swift>
swiftlint --quiet --no-cache <abs/path/to/EditedTest.swift>
```

## Constraints

- Run `swift test` from this repo's checkout root (`testing.mdc`).
- Any production timeout under test must be **≥ 2s**; losers of a timeout race need a
  clear margin (`testing.mdc`).
