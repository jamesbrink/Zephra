# Portable multi-host evidence

See [qualification report](../../multi-host-validation.md) for source revisions,
methods and limits. All images were captured from Simulator and visually inspected.
Gray media are intentional frozen fixture placeholders.

| Capture | Scope |
| --- | --- |
| [1 host](library-1-hosts.jpg), [2 hosts](library-2-hosts.jpg), [4 hosts](library-4-hosts.jpg), [8 hosts](library-8-hosts.jpg) | Final `e2dee21`, light, default text |
| [Today](today-accessibility.jpg), [waiting run](waiting-accessibility.jpg) | Final `e2dee21`, dark, largest accessibility text |
| [Library](library-accessibility.jpg) | `1b30c0a`, unchanged in final layout patch, dark/largest text |
| [Composer top](composer-accessibility-top.jpg), [controls](composer-accessibility-controls.jpg) | Qualification composer layout, unchanged in final patch, dark/largest text |
| [Host details](host-accessibility.jpg) | Qualification native Form, unchanged visually in final patch, dark/largest text |
| [Reference owners](reference-owners.jpg) | Owner badges; subsequent label-placement correction was verified in accessibility snapshots |

`library-matrix.json` and `today-accessibility.json` preserve semantic targets.
`test-results.json` preserves summaries and full-local-log hashes, including the
failed relay attempt. `relay-matrix-events.log` is the final successful live matrix.
The disruption logs contain only temporary qualification connections and routing
metadata, never keys, pairing codes or encrypted payloads.

`scroll-profile.json.gz` is processed ETTrace JSON with top-level nodes, compressed
losslessly; `scroll-profile.txt` is its analysis. Inclusive percentages can exceed
100% when the same symbol appears at multiple stack depths; they are not additive.
