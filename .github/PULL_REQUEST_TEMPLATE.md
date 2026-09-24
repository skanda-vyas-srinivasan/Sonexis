## What changed

Describe the problem and the solution.

## User impact

Describe the affected workflow and any visible or audible behavior change.

## Change classification

Select every affected area. Automatic labels based on changed files will help reviewers confirm this classification.

- [ ] Audio engine or DSP
- [ ] Capture, output, or routing
- [ ] Presets, workspace, models, or persisted data
- [ ] User interface or accessibility
- [ ] Audio Unit plug-ins
- [ ] Build, permissions, dependencies, or release tooling
- [ ] Tests or documentation only

Risk level: <!-- Replace this comment with Low, Medium, or High -->

- **Low:** Documentation, tests, or an isolated non-behavioral change.
- **Medium:** Ordinary UI or internal behavior with limited blast radius.
- **High:** Real-time audio, routing, recording, persistence format, permissions, dependencies, or release behavior.

## Verification

List the exact build and test commands you ran and their results.

### Manual checks

Describe the real app, audio-device, listening, or visual checks performed. If none were performed, write **Not tested manually** and explain why.

### Not tested

List relevant scenarios that remain unverified. A clear limitation is preferable to an unsupported claim.

## Compatibility and risk

- [ ] Preset/workspace compatibility is unchanged or migration behavior is documented.
- [ ] Real-time audio code does not allocate, block, log, or access UI/file APIs.
- [ ] New or changed behavior has regression coverage.
- [ ] UI changes were checked at narrow and wide sizes and include images when useful.
- [ ] Hardware-only or unverified behavior is clearly identified.
- [ ] I reviewed the automatically applied risk and validation labels and called out any mismatch.
