# JobAsProduct

Demonstrates the Swarm job-as-product surface: `JobTask` with an
expected-output contract, `Job.run(_:tasks:merge:)` returning results keyed
by task name plus a merged summary, observer forwarding, and the
manager-delegation recipe (`Job.delegate`).

Deterministic: scripted stub agents, no API keys or devices required.

```sh
swift run JobAsProduct
```
