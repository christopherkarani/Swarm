# Swarm Documentation Improvement Plan

**Target Score: 90+/100**  
**Current Score: 72/100**  
**Gap to Close: 18 points**

---

## Current State Analysis

Based on the comprehensive API quality assessment and front-facing API reference, here's the current documentation landscape:

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| DocC Coverage | ~35% | 90% | 55% |
| README Accuracy | 75% | 95% | 20% |
| Website Alignment | 60% | 90% | 30% |
| Cross-Channel Consistency | 55% | 85% | 30% |
| Code Example Freshness | 65% | 95% | 30% |

### Key Documentation Debt

1. **Multi-Generation API Coexistence**: README examples use mixed V1/V2/V3 syntax
2. **Missing DocC**: ~140 of 220 public types lack documentation comments
3. **Outdated Guides**: Getting started guide references deprecated `AgentBuilder` DSL
4. **Type Erasure Leakage**: Users see `AnyHandoffConfiguration`, `AnyJSONTool` in autocomplete
5. **Inconsistent Terminology**: "Memory" vs "Session" used interchangeably

---

## Gap Analysis

### By Documentation Channel

| Channel | Current State | Issues | Target Score |
|---------|--------------|--------|--------------|
| **DocC** | Sparse coverage; major types like `Agent`, `Workflow`, `Conversation` partially documented | 140+ types undocumented; no documentation for 15+ error types | 90% coverage |
| **README** | Uses outdated `VectorMemory` constructor; mixed API versions in examples | Quick Start uses correct V3 API but advanced examples use deprecated patterns | 95% accuracy |
| **API Catalog** | Lists all types but lacks usage guidance | Missing "when to use" guidance for agent strategies | 90% usefulness |
| **Guides** | Getting started guide references deprecated DSL | `AgentBuilder` examples need replacement with direct init | 85% freshness |
| **Website** | Partially synced with current API | Needs update for V3 canonical API | 90% alignment |

### Critical Gaps by Component

| Component | Gap | Impact on Score |
|-----------|-----|-----------------|
| Agent Initializers | 4 overloads confuse documentation examples | Human DX -0.3, Agent DX -0.2 |
| Guardrail API | Multiple types (`InputGuard`, `InputGuardrail`, `ClosureInputGuardrail`) without guidance | Naming Quality -0.3 |
| Memory/Session Duality | Two protocols documented as separate concepts | Human DX -0.4 |
| Error Types | 15+ error enums without unified handling docs | Error Quality -0.3 |
| Workflow Orchestration | Concrete types (`SequentialChain`, `ParallelGroup`) exposed vs operators | Swift 6.2 Elegance -0.3 |

---

## Improvement Priorities

### P0 (Must Have for 90+ Score)

These items directly address the 18-point gap and align with the API redesign plan phases.

#### 1. Add DocC to All Critical Public Types
**Target files:**
- [ ] `Sources/Swarm/Agents/Agent.swift` — V3 canonical init documentation
- [ ] `Sources/Swarm/Core/AgentConfiguration.swift` — Tiered sub-struct docs
- [ ] `Sources/Swarm/Workflow/Workflow.swift` — Composition method examples
- [ ] `Sources/Swarm/Core/Conversation.swift` — Multi-turn conversation patterns
- [ ] `Sources/Swarm/Memory/AgentMemory.swift` — Factory method documentation

**Expected score gain:** +4 points (Agent DX +0.3, Human DX +0.2)

#### 2. Update README Quick Start to V3 API
**Changes needed:**
- [ ] Replace `VectorMemory(embeddingProvider:...)` with `AnyMemory.vector(provider:...)`
- [ ] Update streaming example to use grouped `AgentEvent` cases (7 groups, not 28 flat)
- [ ] Ensure all examples use `@ToolBuilder` trailing closure syntax
- [ ] Add note about deprecated API removal

**Expected score gain:** +3 points (Human DX +0.3, Agent DX +0.2)

#### 3. Document Factory Discovery Pattern
**New documentation:**
- [ ] `InferenceProvider.` factories (`.anthropic`, `.openAI`, `.ollama`, etc.)
- [ ] `AnyMemory.` factories (`.conversation`, `.vector`, `.summary`, `.sliding`)
- [ ] `RetryPolicy.` presets (`.standard`, `.aggressive`, `.immediate`, `.noRetry`)
- [ ] `GuardrailSpec` static factories (`.maxInput`, `.customInput`, etc.)

**Expected score gain:** +3 points (Agent DX +0.3, Surface Efficiency +0.2)

#### 4. Consolidate Error Documentation
**Actions:**
- [ ] Document unified `SwarmError` type with nested cases
- [ ] Add migration guide from 15+ error types to unified type
- [ ] Document error helper properties (`isRetryable`, `userFacingMessage`)

**Expected score gain:** +2 points (Error Quality +0.3, Human DX +0.1)

#### 5. Update Getting Started Guide
**File:** `docs/guide/getting-started.md`
- [ ] Remove all `AgentBuilder` DSL examples
- [ ] Replace with V3 canonical `Agent(instructions:) { tools }` syntax
- [ ] Update memory initialization examples
- [ ] Add section on choosing agent strategy (toolCalling vs ReAct vs PlanAndExecute)

**Expected score gain:** +2 points (Human DX +0.2)

### P1 (Should Have)

#### 6. Add Usage Examples to All Protocols
**Protocols needing examples:**
- [ ] `InferenceProvider` — custom provider implementation
- [ ] `Memory` — custom memory implementation
- [ ] `AgentObserver` — tracing and metrics collection
- [ ] `InputGuardrail` / `OutputGuardrail` — custom guardrail creation

**Expected score gain:** +2 points (Power & Extensibility +0.2)

#### 7. Document Orchestration Patterns
**New sections:**
- [ ] Sequential composition with `-->` operator
- [ ] Parallel composition with `parallel()` and merge strategies
- [ ] Dynamic routing with `route()`
- [ ] Supervisor pattern with `SupervisorAgent` DSL

**Expected score gain:** +1 point (Agent DX +0.1)

#### 8. Tool Authoring Guide
**Content:**
- [ ] `@Tool` macro deep dive with parameter types
- [ ] `FunctionTool` for closure-based tools
- [ ] `ToolArguments` typed access patterns
- [ ] Bridging to `AnyJSONTool` (internal, but authors should understand)

**Expected score gain:** +1 point (Human DX +0.1)

### P2 (Nice to Have)

#### 9. Architecture Diagrams
- [ ] System architecture diagram (framework layers)
- [ ] Agent execution flow diagram
- [ ] Memory hierarchy diagram
- [ ] Workflow composition patterns visual guide

**Expected score gain:** +0.5 points (Human DX +0.05)

#### 10. Interactive Playground
- [ ] Xcode Playground with runnable examples
- [ ] Step-by-step agent building exercises
- [ ] Multi-agent orchestration patterns

**Expected score gain:** +0.5 points (Human DX +0.05)

#### 11. Migration Guides
- [ ] V1 → V2 migration guide (archive)
- [ ] V2 → V3 migration guide (active)
- [ ] Deprecation timeline and sunset dates

**Expected score gain:** +0.5 points (Error + Migration Quality +0.1)

---

## Implementation Roadmap

### Phase 1: Critical DocC Coverage (Week 1)
**Goal:** Bring DocC coverage from 35% to 65%

**Tasks:**
| Day | Task | Files | Owner |
|-----|------|-------|-------|
| 1-2 | Document `Agent` struct and initializers | `Agent.swift`, `Agent+ConduitProvider.swift` | — |
| 2-3 | Document `Workflow` composition | `Workflow.swift` | — |
| 3-4 | Document `Conversation` actor | `Conversation.swift` | — |
| 4-5 | Document memory factories | `AgentMemory.swift` | — |
| 5 | Document configuration tiers | `AgentConfiguration.swift` | — |

**Deliverables:**
- All P0 DocC tasks complete
- DocC coverage verification script
- Expected score gain: **+5 points**

### Phase 2: README & Quick Start Refresh (Week 1-2)
**Goal:** 95% API accuracy in primary examples

**Tasks:**
| Day | Task | Verification |
|-----|------|--------------|
| 1 | Audit all README code examples | Create test file with all examples |
| 2 | Update Quick Start to V3 | Ensure it compiles and runs |
| 3 | Update multi-agent examples | Test workflow examples |
| 4 | Update memory examples | Replace `VectorMemory` with `AnyMemory.vector` |
| 5 | Update streaming examples | Use grouped `AgentEvent` cases |
| 6-7 | Full README proofread | Cross-check against front-facing-api.md |

**Deliverables:**
- Updated README.md
- `Tests/SwarmTests/Documentation/READMEExamplesCompile.swift` — ensures all examples compile
- Expected score gain: **+3 points**

### Phase 3: Guides Update (Week 2)
**Goal:** Remove all deprecated API references from guides

**Tasks:**
| Day | Task | File |
|-----|------|------|
| 1-2 | Rewrite Getting Started | `docs/guide/getting-started.md` |
| 3 | Update Why Swarm guide | `docs/guide/why-swarm.md` |
| 4 | Update API Catalog examples | `docs/reference/api-catalog.md` |
| 5 | Create Factory Discovery guide | `docs/guide/factory-discovery.md` |

**Deliverables:**
- Refreshed guides with V3 API only
- New factory discovery documentation
- Expected score gain: **+2 points**

### Phase 4: Error & Migration Documentation (Week 2-3)
**Goal:** Unified error handling documented, migration path clear

**Tasks:**
| Day | Task | Output |
|-----|------|--------|
| 1 | Document `SwarmError` unified type | DocC comments in `AgentError.swift` |
| 2 | Create error handling guide | `docs/guide/error-handling.md` |
| 3 | Write V2→V3 migration guide | `docs/guide/migration-v2-v3.md` |
| 4 | Document all deprecated APIs | Deprecation annotations with messages |

**Deliverables:**
- Complete error documentation
- Migration guide published
- Expected score gain: **+2 points**

### Phase 5: Validation & Polish (Week 3)
**Goal:** Cross-channel consistency, final score validation

**Tasks:**
| Day | Task | Method |
|-----|------|--------|
| 1 | Cross-check all channels | Compare README, guides, DocC, website |
| 2 | Run documentation tests | `swift test --filter Documentation` |
| 3 | DocC coverage report | `xcrun docc coverage` or equivalent |
| 4 | Agent DX spot-check | Simulate agent using only docs |
| 5 | Final score calculation | Run API quality assessment |

**Deliverables:**
- Consistency report
- Final score: **90+/100**

---

## Success Metrics

### Quantitative Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| DocC Coverage | ~35% | 90%+ | Lines of public API with DocC / total public API lines |
| README Example Accuracy | 75% | 95%+ | Examples that compile without modification / total examples |
| Cross-Channel Consistency | 55% | 85%+ | API patterns consistent across all channels |
| Type Documentation | ~80 types | 200+ types | Public types with documentation comments |
| Guide Freshness | 60% | 90%+ | Guide examples using V3 API / total examples |

### Qualitative Metrics

1. **First-Try Success Rate**
   - A developer can create a working agent from README alone
   - A coding agent selects correct API on first autocomplete suggestion

2. **Progressive Disclosure**
   - Simple use cases require reading only Quick Start
   - Advanced features discoverable through DocC "See Also" links

3. **Error Recovery**
   - All error types document recovery strategies
   - Deprecated APIs have migration messages

---

## Documentation Quality Gates

Before marking the improvement plan complete, these gates must pass:

### Gate 1: DocC Coverage
```bash
# Verify 90%+ public API has documentation
swift doc coverage --target Swarm 2>&1 | grep "Coverage"
# Expected: 90% or higher
```

### Gate 2: Example Compilation
```bash
# All README examples compile
swift test --filter READMEExamplesCompile
# Expected: PASS
```

### Gate 3: API Consistency
```bash
# No deprecated APIs in README or guides
grep -r "AgentBuilder\|AgentLoop\|RelayAgent\|ClosureInputGuardrail" docs/ README.md
# Expected: No matches (except in migration guides)
```

### Gate 4: Terminology Consistency
```bash
# Consistent use of "Memory" (not "Session") for conversation history
grep -r "Session" docs/guide/getting-started.md | grep -v "sessionId"
# Expected: No inappropriate "Session" usage
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| API changes during documentation | Document only stabilized V3 API; mark experimental APIs as such |
| Documentation drift after updates | Add CI check: examples must compile |
| Incomplete coverage | Use DocC coverage report; prioritize by API usage frequency |
| Inconsistent terminology | Create terminology glossary; review all docs for consistency |

---

## Appendix: Documentation Inventory

### Existing Documentation Files

| File | Type | Status | Priority |
|------|------|--------|----------|
| `README.md` | Entry point | Needs V3 update | P0 |
| `docs/guide/getting-started.md` | Tutorial | Outdated (V1/V2) | P0 |
| `docs/guide/why-swarm.md` | Conceptual | Current | P2 |
| `docs/reference/api-catalog.md` | Reference | Partially outdated | P1 |
| `docs/reference/front-facing-api.md` | Reference | Current (canonical) | Reference |
| `docs/reference/api-quality-assessment.md` | Internal | Current | Reference |
| `docs/reference/overview.md` | Overview | Needs refresh | P1 |
| `docs/plans/2026-03-07-swarm-api-90-score-redesign.md` | Plan | Current | Reference |

### New Documentation Needed

| File | Type | Priority |
|------|------|----------|
| `docs/guide/factory-discovery.md` | Tutorial | P1 |
| `docs/guide/error-handling.md` | Tutorial | P1 |
| `docs/guide/migration-v2-v3.md` | Migration | P2 |
| `docs/guide/tool-authoring.md` | Tutorial | P1 |
| `docs/reference/terminology.md` | Reference | P2 |

---

## Related Documents

- [API Quality Assessment](./api-quality-assessment.md) — Detailed scoring breakdown
- [Front-Facing API](./front-facing-api.md) — Canonical V3 API reference
- [API Redesign Plan](../plans/2026-03-07-swarm-api-90-score-redesign.md) — Implementation phases

---

*Last Updated: 2026-03-19*  
*Target Completion: 3 weeks*  
*Projected Final Score: 90-92/100*
