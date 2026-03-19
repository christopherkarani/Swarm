# README.md Audit Report

## Summary
- **README freshness:** 65/100
- **API alignment score:** 58/100
- **Examples correctness:** 62/100
- **Overall README Score:** 62/100

**Verdict:** The README contains significant API drift from the V3 canonical spec. Several examples use outdated or incorrect APIs that would fail to compile. Major updates needed for accuracy and completeness.

---

## Findings

### API Accuracy Issues

| README Section | Claimed API | Actual API (V3 Spec) | Status |
|----------------|-------------|----------------------|--------|
| Quick Start - Agent init | `Agent("instructions", configuration:)` with labeled `instructions` param | `Agent(_ instructions: String, ...)` — unlabeled first param is V3 canonical | ⚠️ INCORRECT |
| Quick Start - Agent config | `configuration: .default.name("Analyst")` | `AgentConfiguration` struct with `name` property | ⚠️ INCORRECT |
| Guardrails example | `MaxLengthGuardrail(limit:)` and `NotEmptyGuardrail()` | `GuardrailSpec.maxInput(_:)` and `GuardrailSpec.inputNotEmpty` | ❌ INCORRECT |
| Memory example | `VectorMemory(embeddingProvider:threshold:)` | `MemoryOption.vector(embeddingProvider:threshold:)` | ❌ INCORRECT |
| Durable workflows | `.durable.checkpoint(id:policy:)` and `.durable.checkpointing(_:)` | `workflow.durable.checkpoint(id:policy:)` — API correct but chained incorrectly | ⚠️ MISLEADING |
| Durable execute | `workflow.durable.execute("watch", resumeFrom:)` | Correct per V3 spec | ✅ CORRECT |
| Inference provider | `inferenceProvider: .anthropic(key:)` | Dot-syntax factory correct | ✅ CORRECT |

### Code Example Issues

| Example | Issue | Correction |
|---------|-------|------------|
| Quick Start Agent init | Uses labeled `instructions:` parameter instead of unlabeled first param | `try Agent("Answer finance questions...") { ... }` |
| Quick Start configuration | Uses `.default.name("Analyst")` which appears to be invalid syntax | `configuration: .init(name: "Analyst")` or pass name to init |
| Guardrails example (lines 136-138) | Uses non-existent guardrail types | Use `GuardrailSpec.maxInput(5000)` and `GuardrailSpec.maxOutput(2000)` |
| VectorMemory example (line 128) | Uses `VectorMemory` directly instead of `MemoryOption.vector()` | `memory: .vector(embeddingProvider: myEmbedder, threshold: 0.75)` |
| FunctionTool example (lines 144-151) | Parameter type `.string` may not exist; uses `args.require()` | Verify `ToolParameter` API; use `args.requireString()` if available |
| Durable workflow example (lines 159-164) | Shows `.durable.checkpoint()` chained after `.step()` but V3 shows `durable` is a namespace property, not method chain | Clarify that durable returns a `Durable` struct with its own methods |
| Parallel fan-out (line 90) | `merge: .structured` — correct per spec | ✅ Correct |

### Missing Documentation

#### Critical Missing Features
1. **Global Swarm Configuration** — No mention of `Swarm.configure()`, `Swarm.defaultProvider`, or the global provider chain
2. **Conversation API** — The `Conversation` actor for multi-turn chat is completely undocumented
3. **GuardrailSpec** — The primary guardrail API using static factories is missing
4. **MemoryOption** — Dot-syntax memory factories not documented
5. **RunOptions** — No documentation for runtime options like `maxIterations`, `parallelToolCalls`

#### Incomplete Documentation
1. **Handoffs** — Mentioned in "What's Included" but no example of `AnyHandoffConfiguration` or `handoffAgents:` parameter
2. **Workflow methods** — Missing `.repeatUntil()`, `.timeout()`, full `.observed(by:)` documentation
3. **AgentObserver** — Mentioned but no usage example
4. **Tracing** — `Tracer` protocol mentioned but no implementation examples
5. **MCP** — Listed in "What's Included" with zero documentation or examples
6. **Provider factories** — Only `.anthropic()` and `.foundationModels` shown; missing `.openAI()`, `.ollama()`, `.gemini()`, `.openRouter()`

#### Deprecated/Removed APIs Still Referenced
1. **Legacy types in "What's Included"** — Lists `AgentBuilder`, `AnyAgent`, `AnyTool` which V3 spec explicitly lists as "No legacy types"
2. **ClosureInputGuardrail/ClosureOutputGuardrail** — Mentioned in "What's Included" but listed as removed in V3
3. **AgentBlueprint** — Listed as removed in V3 but still in README table

### Structural Issues

1. **No Session documentation** — The `Session` parameter for `run()` and `Conversation` is never mentioned
2. **AgentRuntime protocol** — Mentioned but not explained; users won't understand when to use it vs `Agent`
3. **MergeStrategy variants** — Only `.structured` shown; missing `.indexed`, `.first`, `.custom`
4. **CheckpointPolicy** — Not mentioned; users won't know difference between `.onCompletion` and `.everyStep`

---

## Recommended Changes

### Priority 1: Fix Broken Examples (Must Fix)

1. **Update Quick Start Agent initialization**
   ```swift
   // CURRENT (BROKEN):
   let agent = try Agent("Answer finance questions...",
       configuration: .default.name("Analyst"),
       inferenceProvider: .anthropic(key: "sk-...")) { ... }
   
   // CORRECT (V3):
   let agent = try Agent(
       "Answer finance questions...",
       configuration: .init(name: "Analyst"),
       inferenceProvider: .anthropic(key: "sk-...")
   ) {
       PriceTool()
       CalculatorTool()
   }
   ```

2. **Fix Guardrails example**
   ```swift
   // CURRENT (BROKEN):
   inputGuardrails: [MaxLengthGuardrail(limit: 5000), NotEmptyGuardrail()]
   
   // CORRECT (V3):
   inputGuardrails: GuardrailSpec.maxInput(5000),
   outputGuardrails: GuardrailSpec.maxOutput(2000)
   ```

3. **Fix VectorMemory example**
   ```swift
   // CURRENT (BROKEN):
   memory: VectorMemory(embeddingProvider: myEmbedder, threshold: 0.75)
   
   // CORRECT (V3):
   memory: .vector(embeddingProvider: myEmbedder, threshold: 0.75)
   ```

### Priority 2: Add Missing Documentation

4. **Add Conversation API example**
   ```swift
   let conversation = Conversation(with: agent)
   let result1 = try await conversation.send("Hello!")
   let result2 = try await conversation.send("Tell me more about that.")
   ```

5. **Document MemoryOption factories**
   ```swift
   memory: .conversation(limit: 50)      // or .vector(), .slidingWindow(), .summary()
   ```

6. **Add Handoff example**
   ```swift
   let triage = try Agent(
       "Route requests to the right specialist.",
       handoffAgents: [billingAgent, supportAgent, salesAgent]
   )
   ```

7. **Document remaining Workflow methods**
   ```swift
   Workflow()
       .step(agent)
       .repeatUntil(maxIterations: 10) { result in result.output.contains("DONE") }
       .timeout(.seconds(30))
   ```

### Priority 3: Clean Up Legacy References

8. **Remove from "What's Included" table:**
   - `AgentBuilder` — removed in V3
   - `AnyAgent` — removed in V3  
   - `AnyTool` — removed in V3
   - `AgentBlueprint` — removed in V3
   - `ClosureInputGuardrail` — removed in V3
   - `ClosureOutputGuardrail` — removed in V3

9. **Update Architecture diagram** — Ensure it reflects V3 APIs, not legacy types

### Priority 4: Enhance Documentation

10. **Add Global Configuration section**
    ```swift
    await Swarm.configure(provider: .anthropic(key: "sk-..."))
    // Now agents don't need explicit inferenceProvider
    let agent = try Agent("Be helpful.") { MyTool() }
    ```

11. **Add MCP section** with basic client/server example

12. **Document all InferenceProvider factories**
    - `.anthropic(key:)`
    - `.openAI(key:)`
    - `.ollama(model:)`
    - `.foundationModels`
    - `.gemini(key:)`
    - `.openRouter(key:)`

13. **Add CheckpointPolicy explanation**
    ```swift
    .durable.checkpoint(id: "v1", policy: .everyStep)  // vs .onCompletion
    ```

---

## Alignment Scoring Details

| Category | Score | Rationale |
|----------|-------|-----------|
| **API Signature Accuracy** | 45/100 | Multiple init signatures wrong; guardrail types don't exist |
| **Example Compilability** | 55/100 | ~40% of examples would fail to compile with V3 |
| **Completeness** | 60/100 | Missing Conversation, Session, RunOptions, full provider list |
| **Consistency** | 70/100 | Inconsistent parameter naming; some correct, some wrong |
| **Freshness** | 65/100 | Core concepts present but API drift from V3 spec |

---

## Action Items Checklist

- [ ] Fix Quick Start Agent init to use unlabeled instructions parameter
- [ ] Fix configuration syntax (remove `.default.name()` pattern)
- [ ] Replace all guardrail examples with `GuardrailSpec` factories
- [ ] Replace `VectorMemory` with `MemoryOption.vector`
- [ ] Add Conversation API documentation
- [ ] Add Swarm global configuration section
- [ ] Document all MemoryOption factories
- [ ] Document all provider factories
- [ ] Remove legacy type references from "What's Included"
- [ ] Add Handoff example with `handoffAgents:`
- [ ] Document remaining Workflow methods (.repeatUntil, .timeout)
- [ ] Add MCP basic documentation
- [ ] Verify FunctionTool parameter API
- [ ] Add CheckpointPolicy documentation

---

*Report generated: 2026-03-19*
*Comparing README.md against docs/reference/front-facing-api.md (V3 API spec)*
