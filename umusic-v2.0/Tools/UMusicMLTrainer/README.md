# uMusic ML Trainer

The first supported artifact is a boosted-tree cold-start prior trained from
deterministic curated listening scenarios. It provides useful ranking before personal
history exists and proves Core ML compilation, directory hashing, signing, canary
inference, diagnostics, and heuristic fallback. It is not population-trained or
personalized evidence.

Generate a private Curve25519 signing key outside the repository, then run:

```sh
swift -module-cache-path /tmp/umusic-swift-module-cache \
  Tools/UMusicMLTrainer/train.swift --bootstrap \
  --output Sources/UMusicCore/Resources \
  --signing-key /secure/path/umusic-model-signing-key.bin
```

Never commit the private key. The generated public key, signed manifest, compiled
model, and training report are safe application resources. Personalized training from
`.umusicresearch` is not implemented until the export can reconstruct the exact eight
ranker features without future-data leakage.
