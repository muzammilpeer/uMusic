# Audio-analysis model provenance

No third-party model weights are committed or enabled by Sprint 20's first vertical slice.

| Provider | Artifact | Code license | Weight license | Status |
|---|---|---|---|---|
| `deterministic` | `checksum-fixture-1` | uMusic source | none | Enabled for development and contract tests; does not inspect audio or claim musical meaning |
| MERT | `m-a-p/MERT-v1-95M`, revision `12af15fef9d0ac838c3f475bfbbf26d2060dd4f5` | Repository and weight licenses reviewed separately | Published checkpoint is marked CC BY-NC 4.0 | Approved for this private noncommercial hobby deployment; installed outside Git and validated against the private library on 2026-08-11 |

Deployment uses three bounded five-second excerpts per track, 24 kHz mono decoding,
last-layer temporal mean pooling, excerpt mean pooling, and a deterministic 64-component
random projection (`mean-last-rp64-v1`). The stored vectors are L2-normalized Float16.
This deployment derives an RMS-based energy scalar; it does not claim that base MERT
directly predicts genre, language, mood, religious content, BPM, or valence.

Cached artifact SHA-256 values:

- `pytorch_model.bin`: `a2b8b747f72c06e0595aeae41ae5473f4364938c6b39b2c58be38c48e6bd3fcd`
- `config.json`: `ea2627c4c7825cd66f3c944b6b966331604c35928174e0100cd4a82829424e32`
- `preprocessor_config.json`: `cc5a5e4a5d3b1a758a5ed984b2eaa15bb0522d811d44a9eed82bfca4baa0dc8f`
- `modeling_MERT.py`: `6c3ee73cef6f0c30ef494f88d96f891fa6925ffe663fa391b512f4b57abecc6c`
- `configuration_MERT.py`: `ae0ec2bab8f59c724ba9878a7c20b67210189536ea62d34a56775968e9decb03`

After these hashes were recorded, the deployed worker was switched to local-files-only
model loading. It requires no internet access for subsequent song analysis.

The production adapter must record repository URL and revision, exact checkpoint URL and
SHA-256, model-card revision, licenses, intended use, redistribution policy, input sampling
contract, output layer/pooling, projection artifact/version, and evaluation results. Model
weights, private MP3 excerpts, real embeddings, and listening telemetry remain outside Git.
