# Swarm

On-device and Linux agents: one Agent runs a conversation against an InferenceProvider, with tools, memory, and optional multi-agent Workflow.

## Language

**Agent**:
A configured actor that takes a user turn and produces an AgentResult — tools, memory, guardrails, and handoffs included.
_Avoid_: assistant, bot, runtime (say AgentRuntime only for the protocol)

**InferenceProvider**:
The backend that produces one model turn. Callers pass `[InferenceMessage]` and call generate, stream, tool-calling, and structured output on the same interface. Capabilities say which of those the adapter actually supports.
_Avoid_: LLM, model client, completion API, prompt provider

**Capabilities**:
The features an InferenceProvider advertises — streaming, native tool calling, structured outputs, private inference, provider-owned tool loop. Callers read this bitset; they do not probe extra protocols.
_Avoid_: protocol ladder, optional conformance, feature flags (too generic)

**InferenceMessage**:
One role-tagged item on the InferenceProvider seam: system, user, assistant, or tool. Agent sends these in; a finished provider-owned turn returns them as the inner transcript.
_Avoid_: prompt, chat turn (ambiguous with Agent run), completion, MemoryMessage (as the provider transcript)

**Provider-owned tool loop**:
An InferenceProvider adapter constructed to iterate tool calls and return a finished turn. Agent supplies tool execution for that run, reads Capabilities, and does not iterate. Agent does not choose this per run.
_Avoid_: native session, Apple loop, Foundation Models execution mode, AgentConfiguration switch, TaskLocal hook

**Context windowing**:
Cutting `[InferenceMessage]` down to a token budget. Roles stay. This is not a flatten to one user string.
_Avoid_: prompt stuffing, envelope rewrite (as what the provider sees)

**Text-only backend**:
A prompt-shaped inner type: generate, stream, and tool-calling on a `String`. It cannot take `InferenceMessage` roles. Production string models and test fakes are adapters at this seam.
_Avoid_: prompt provider, string provider, PromptInferenceProvider

**Text-only adapter**:
The InferenceProvider adapter that flattens `[InferenceMessage]` into a string and forwards to a text-only backend. Agent never sees the backend directly; callers wrap via a factory.
_Avoid_: prompt path, string provider
