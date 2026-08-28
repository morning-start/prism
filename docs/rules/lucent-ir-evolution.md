# Lucent IR Evolution Checklist

This checklist governs changes to Lucent IR fields, enum variants, stream events, capabilities, request extensions, and response payloads.

1. Describe the protocol feature and whether it affects conversion, SDK or Agent consumption, or both.
2. Update the formal IR design before implementation.
3. Define fidelity for every affected provider: Exact, Degraded, or Unsupported.
4. Preserve unknown data where practical through provider payloads or diagnostics.
5. Add request, response, and stream regression tests for source and target providers.
6. Review generated .mbti changes and document compatibility.
7. Run native and WASM test suites.

No IR change is complete until its fidelity boundary and compatibility impact are explicit.
