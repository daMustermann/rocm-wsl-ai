## What this changes

<!-- One or two sentences. Link the issue it closes, if there is one: "Closes #123". -->

## Type of change

- [ ] Bug fix
- [ ] New tool in the registry (`lib/tools.sh`)
- [ ] Performance change
- [ ] Documentation
- [ ] Refactor / internal cleanup

## Checklist

- [ ] Every shell script I touched passes `bash -n` (e.g. `bash -n lib/launch.sh scripts/start/comfyui.sh`).
- [ ] `python3 scripts/utils/perf_engine.py doctor` still passes on my machine, and I pasted its output below.
- [ ] Any performance claim in this PR comes with **measured** numbers from `python3 scripts/utils/perf_engine.py bench`, not an estimate or something read in a forum thread.
- [ ] I did not commit anything from `~/.config/rocm-wsl-ai/` (`user.env`, `perf.env`, `perf_profile.json`, `tools.local`, `miopen/`, `logs/`). This is per-machine state, it is in `.gitignore`, and it must stay out of the repository.
- [ ] No personal paths, GPU serial numbers, hostnames or tokens anywhere in the diff.
- [ ] I ran the rest of the local checks in [CONTRIBUTING.md](../CONTRIBUTING.md) (shellcheck, `compileall`, `bash -n` / `py_compile` over the tree).

## Verification

<!--
  Paste real output. For anything performance-related, include the bench summary:
  which candidates were measured, and whether the result was conclusive or within
  the noise floor (a <3% difference is reported as noise and nothing is applied).

  Hardware matters: GPU model, ROCm version, and whether you were in WSL2.
-->

```
$ python3 scripts/utils/perf_engine.py doctor
...

$ bash -n <changed scripts>
(no output = OK)
```

## Notes for reviewers

<!--
  Anything a reviewer should know: a deliberate trade-off, a fix that looks odd but
  is not, a follow-up you intentionally left out, or a part you are unsure about.
  If your change touches lib/launch.sh, say whether you re-tested a real launch.
-->
