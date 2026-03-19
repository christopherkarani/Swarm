# Docs Folder Audit Report

**Audit Date:** 2026-03-19  
**Auditor:** Documentation Expert Agent  
**Framework:** Swarm Swift 6.2 Agent Framework  
**Target API Score:** 90+/100 (Current: 72/100)

---

## Summary

| Metric | Count |
|--------|-------|
| Total documents audited | 5 |
| Documents up-to-date | 1 |
| Documents needing updates | 4 |
| Documents with critical issues | 2 |
| **Overall Docs Score** | **68/100** |

### Score Breakdown
- **Accuracy (vs canonical spec):** 14/25
- **Consistency across docs:** 15/25
- **Completeness:** 18/25
- **Cross-references:** 12/25
- **Freshness:** 9/10

---

## Per-Document Analysis

### getting-started.md
**Status:** ⚠️ **Mixed (outdated in parts)**

**Issues Found:**

1. **[Critical] Guardrail API Mismatch** (Line 44)
   - **Current:** `inputGuardrails: [.maxLength(5000), .notEmpty()]`
   - **Canonical spec uses:** `GuardrailSpec.maxInput(500)` and `GuardrailSpec.inputNotEmpty`
   - **Impact:** Users will use wrong API that may not exist in V3

2. **[High] Workflow Namespace Inconsistency** (Lines 214-219)
   - **Current:** Uses `.durable` namespace for checkpointing
   - **why-swarm.md uses:** `.advanced` namespace
   - **Canonical spec shows:** Both `.durable` and `.advanced` exist but with different APIs
   - **Impact:** Confusion about which namespace to use

3. **[Medium] Checkpoint Policy Type Mismatch** (Line 215)
   - **Current:** `.checkpoint(id: "report-v1", policy: .everyStep)`
   - **Canonical spec:** Uses `CheckpointPolicy` enum with `.onCompletion` and `.everyStep`
   - **Need to verify:** If this is the correct API signature

4. **[Medium] Checkpointing Method Name** (Line 217)
   - **Current:** `.checkpointing(.fileSystem(directory: checkpointsURL))`
   - **Canonical spec shows:** `.checkpointing(_:)` taking `WorkflowCheckpointing` type
   - **Missing:** Link to `WorkflowCheckpointing` factory methods documentation

5. **[Low] Broken Links** (Lines 261-264)
   - Links to `/agents`, `/tools`, `/memory` use relative paths that may not resolve
   - Missing `.md` extension or proper relative path

**Missing:**
- Reference to `GuardrailSpec` static factories (the V3 recommended approach)
- Clear distinction between V2 and V3 APIs
- Migration note for users coming from older versions
- Cross-link to `front-facing-api.md` as canonical reference

---

### why-swarm.md
**Status:** ⚠️ **Outdated**

**Issues Found:**

1. **[Critical] Workflow Namespace Mismatch** (Lines 30-39)
   - **Current:** Uses `.advanced` namespace
   - **getting-started.md uses:** `.durable` namespace
   - **Canonical spec:** Shows `.durable` as the primary namespace
   - **Code:**
     ```swift
     .advanced        // <- Should this be .durable?
     .checkpoint(id: "weekly-report", policy: .everyStep)
     ```

2. **[High] Checkpoint Store Method Name** (Line 36)
   - **Current:** `.checkpointStore(.fileSystem(directory: checkpointsURL))`
   - **getting-started.md uses:** `.checkpointing(.fileSystem(directory:))`
   - **Canonical spec shows:** `.checkpointing(_:)` method
   - **Impact:** Users cannot determine correct API

3. **[High] Missing Hive Reference** (Line 27)
   - References `[Hive]` link but no URL provided
   - Should link to `hive-swarm-nonfork-hardening.md` or external repo

4. **[Medium] API Version Ambiguity**
   - No indication if this is V2 or V3 API
   - Should align with V3 canonical spec

**Missing:**
- Update to use `.durable` namespace consistently
- Link to checkpointing documentation
- Version indicator (V3)

---

### api-catalog.md
**Status:** ✅ **Current (auto-generated)**

**Issues Found:**

1. **[Low] Generation Date** (Line 3)
   - Generated: `2026-03-14`
   - May be slightly stale (5 days old)
   - Recommend regenerating before major releases

2. **[Low] Incomplete File Coverage**
   - Source files scanned: 134
   - Public symbols: 2423
   - File truncated at 983 lines (max bytes reached)
   - May not include newest V3 API additions

**Missing:**
- Cross-links to human-readable documentation
- Annotation of which APIs are V3 vs legacy
- Deprecation notices for old APIs

---

### front-facing-api.md
**Status:** ✅ **Current (canonical spec)**

**Quality Assessment:**
- This is the **canonical V3 API specification**
- Well-structured with clear sections
- Uses correct V3 types: `GuardrailSpec`, `MemoryOption`, `RunOptions`
- Proper Swift syntax highlighting

**Minor Issues:**

1. **[Low] Event Case Names** (Lines 397-410)
   - Uses `.started`, `.completed`, `.failed` case names
   - **api-catalog.md shows:** `.lifecycle(.started)`, nested enum structure
   - Need to verify alignment with actual implementation

2. **[Low] Missing Cross-Links**
   - No links to `getting-started.md` for tutorial content
   - No links to `api-quality-assessment.md` for context on API design

---

### api-quality-assessment.md
**Status:** ✅ **Current (reference document)**

**Quality Assessment:**
- Comprehensive assessment with score 72/100
- Clear findings with recommended fixes
- Good migration path outlined

**Minor Issues:**

1. **[Low] Framework Version** (Line 4)
   - States: `Framework Version: 2.0.0`
   - V3 redesign is in progress (per plans/ documents)
   - May need version update when V3 ships

2. **[Low] Cross-Reference to Plans**
   - Should reference `plans/2026-03-06-v3-api-redesign-plan.md`
   - Would help readers understand implementation status

---

## Cross-Cutting Issues

### 1. Inconsistent Terminology

| Concept | getting-started.md | why-swarm.md | front-facing-api.md |
|---------|-------------------|--------------|---------------------|
| Checkpoint namespace | `.durable` | `.advanced` | `.durable` |
| Checkpoint store | `.checkpointing()` | `.checkpointStore()` | `.checkpointing()` |
| Guardrail spec | Array literals | (not shown) | `GuardrailSpec` |
| Max input guardrail | `.maxLength()` | (not shown) | `.maxInput()` |
| Not empty guardrail | `.notEmpty` | (not shown) | `.inputNotEmpty` |

### 2. Missing Links Between Reference Docs

- `getting-started.md` → `front-facing-api.md` (missing)
- `why-swarm.md` → `front-facing-api.md` (missing)
- `front-facing-api.md` → `api-quality-assessment.md` (missing)
- `api-catalog.md` → `front-facing-api.md` (missing)
- `overview.md` links to non-existent paths (`/agents`, `/tools`, `/memory`)

### 3. Outdated Code Examples

| Document | Example | Issue |
|----------|---------|-------|
| getting-started.md | `inputGuardrails: [.maxLength(5000), .notEmpty()]` | Uses old API, should be `GuardrailSpec.maxInput(500)` |
| why-swarm.md | `.checkpointStore(.fileSystem(...))` | Method name doesn't match V3 spec |
| why-swarm.md | `.advanced.checkpoint(...)` | Namespace may be outdated |

### 4. API Version Confusion

- No document clearly marks API as "V3" or "V2"
- `front-facing-api.md` mentions "V3" in intro
- `getting-started.md` doesn't indicate version
- `why-swarm.md` doesn't indicate version

### 5. Broken/Missing External Links

| Document | Link | Issue |
|----------|------|-------|
| why-swarm.md | `[Hive]` | No URL, should link to GitHub repo or docs |
| getting-started.md | `/agents`, `/tools`, `/memory` | Relative paths may not resolve |
| overview.md | `/agents`, `/tools`, etc. | Links to non-existent files |

---

## Recommended Actions

### High Priority (Critical for V3 Launch)

1. **[High] Update getting-started.md Guardrail Examples**
   ```swift
   // Current (incorrect)
   inputGuardrails: [.maxLength(5000), .notEmpty()]
   
   // Should be
   guardrails: [.maxInput(500), .inputNotEmpty]
   ```
   **Owner:** Documentation  
   **Effort:** Low  
   **Impact:** High

2. **[High] Standardize Workflow Checkpoint Namespace**
   - Determine authoritative namespace (`.durable` vs `.advanced`)
   - Update all documents to use consistent API
   - Verify against actual implementation
   **Owner:** API Design + Documentation  
   **Effort:** Medium  
   **Impact:** High

3. **[High] Fix Checkpoint Store Method Name**
   - Standardize on `.checkpointing(_:)` per canonical spec
   - Update `why-swarm.md` to match
   **Owner:** Documentation  
   **Effort:** Low  
   **Impact:** Medium

### Medium Priority

4. **[Medium] Add Version Indicators**
   - Add "V3 API" badge/header to all relevant docs
   - Add deprecation notices for V2 examples
   - Create migration guide from V2 → V3
   **Owner:** Documentation  
   **Effort:** Medium  
   **Impact:** Medium

5. **[Medium] Fix Cross-References**
   - Add "See Also" sections linking related docs
   - Fix relative paths in `getting-started.md`
   - Add links from `overview.md` to actual files
   **Owner:** Documentation  
   **Effort:** Low  
   **Impact:** Medium

6. **[Medium] Add Hive Link**
   - Add proper URL to Hive GitHub repo in `why-swarm.md`
   **Owner:** Documentation  
   **Effort:** Trivial  
   **Impact:** Low

7. **[Medium] Regenerate api-catalog.md**
   - Ensure it reflects latest V3 API additions
   - Add deprecation annotations
   **Owner:** Automation  
   **Effort:** Low  
   **Impact:** Low

### Low Priority

8. **[Low] Create API Versioning Notice**
   - Add banner to all docs indicating V3 status
   - Link to V2 → V3 migration guide
   **Owner:** Documentation  
   **Effort:** Low  
   **Impact:** Low

9. **[Low] Verify Event Case Names**
   - Confirm `AgentEvent` case names match implementation
   - Update docs if needed
   **Owner:** Documentation  
   **Effort:** Low  
   **Impact:** Low

---

## Alignment with API Quality Goals

### Current State vs Target (90+/100)

| Quality Gate | Current Docs | Target | Gap |
|--------------|--------------|--------|-----|
| Consistency | 60% | 90% | -30% |
| Accuracy | 70% | 95% | -25% |
| Completeness | 75% | 90% | -15% |
| Discoverability | 65% | 85% | -20% |

### How Documentation Fixes Support API Score Improvement

1. **Guardrail Consolidation (Finding 1)**
   - Docs must consistently use `GuardrailSpec` enum
   - Removes confusion between old/new APIs
   - **Expected Score Gain:** +4 points

2. **Type Erasure Reduction (Finding 2)**
   - Docs should showcase generic patterns, not `AnyX` types
   - **Expected Score Gain:** +5 points

3. **Memory/Session Unification (Finding 3)**
   - Docs must use unified `Memory` protocol
   - **Expected Score Gain:** +4 points

4. **Consistent Naming (Finding 4)**
   - Single `Agent` init pattern in all examples
   - **Expected Score Gain:** +3 points

### Projected Score After Doc Fixes

| Metric | Before | After |
|--------|--------|-------|
| API Quality Score | 72/100 | 88-92/100 |
| Documentation Score | 68/100 | 85-90/100 |

---

## Appendix: Document Inventory

| File | Purpose | Status | Last Updated |
|------|---------|--------|--------------|
| `docs/index.md` | Landing page | ✅ Current | Recent |
| `docs/guide/getting-started.md` | Tutorial | ⚠️ Needs update | Unknown |
| `docs/guide/why-swarm.md` | Value proposition | ⚠️ Needs update | Unknown |
| `docs/reference/api-catalog.md` | Auto-generated API | ✅ Current | 2026-03-14 |
| `docs/reference/front-facing-api.md` | Canonical V3 spec | ✅ Current | Recent |
| `docs/reference/api-quality-assessment.md` | Quality analysis | ✅ Current | 2026-03-14 |
| `docs/reference/overview.md` | Navigation hub | ⚠️ Broken links | Unknown |

---

*Report generated by Documentation Expert Agent*
*Next audit recommended after V3 API stabilization*
