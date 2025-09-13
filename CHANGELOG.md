# Changelog

All notable changes to this project will be documented in this file.

The format is loosely based on "Keep a Changelog" and follows Semantic Versioning where practical.

## [1.0.0] - 2025-09-13
### Added
- Initial formal release entry (1.0.0).

### Changed
- ComfyUI installer now automatically clones and installs ComfyUI-Manager and ComfyUI-Lora-Manager into `custom_nodes` and installs their requirements when present.
- Automatic1111 (Stable Diffusion WebUI) installer now clones/pulls the latest repository at install/update time and upgrades Python requirements in the toolkit virtual environment. Extension repositories are updated and their requirements are installed when present.
- SD.Next installer now clones/pulls the latest repository at install/update time and upgrades Python requirements in the toolkit virtual environment. A non-destructive quick launch test is attempted when possible.
- ROCm / PyTorch install and verification flows hardened: GPU detection and exported env (HSA_OVERRIDE_GFX_VERSION, PYTORCH_ROCM_ARCH) are centralized and the toolkit now targets RDNA3+ hardware (gfx11xx/gfx12xx) by default.

### Removed
- Removed support and installers/start scripts for the following third-party tools to reduce maintenance surface and focus testing/support on ROCm-compatible workflows:
  - InvokeAI
  - Fooocus
  - SD WebUI Forge

### Documentation
- `README.md` updated to reflect the supported tools and to state that the removed projects are no longer supported by this toolkit.

### Notes
- This release numbers the current baseline as `1.0.0`. Future updates should increment the patch/minor/major version according to the scope of changes.
- If you relied on any of the removed projects, consult their upstream repositories for installation instructions or consider adding them back with dedicated, well-tested installers.

[Unreleased]: https://github.com/daMustermann/rocm-wsl-ai/compare/1.0.0...HEAD
