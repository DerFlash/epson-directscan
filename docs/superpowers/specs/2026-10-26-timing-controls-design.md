# Scan timing controls

User intent: reduce unnecessary delay before saving, measure each step locally,
and make the polling interval adjustable without weakening export guards.
Approved scope is the preceding proposal followed by “tu das”.

Keep the existing AppleScript/JXA app and its one-action-per-poll state machine.
Add pollIntervalMs (integer 100..2000, default 250) with migration for existing
settings. Offer 100/250/500/1000/2000 ms in the existing settings menu. Disabled
or paused helpers retain a two-second idle interval. Do not change action guards,
startup arming, pending reservations, collision checks or 10/30/120-second limits.
Changing only the interval must preserve an in-flight transaction.

Measure monotonic elapsed milliseconds for settings, capture, policy, action and
total poll work. Record active/error polls only in a separate bounded private
128-record timings.json, with runtime-generated timestamp, known phase/status,
action enum and numeric durations only. Expose a local human-readable timing
summary. No paths, titles, pixels or network. Timing failures must not cause
repeated actions. Retain the last successful scan timing while idle.

Existing bridge-only baseline: eight getSettings calls averaged 19.2 ms locally.
The fixed one-second idle delay is larger than this bridge overhead. Requesting
250 ms instead of 1000 ms removes 750 ms of scheduled delay between active polls;
actual OS scheduling, UI reads and Epson processing still affect elapsed time.
Do not claim a physical speedup without a fresh timed scanner run.

Approaches considered: reducing failure timeouts would not accelerate success;
rewriting scheduling with timers would add lifecycle complexity. Keep the native
idle handler and tune its positive numeric return interval instead. No caching
of mutable AppleScript properties in the signed bundle. Source changes and a
local build are authorized; new public release remains a separate action.
