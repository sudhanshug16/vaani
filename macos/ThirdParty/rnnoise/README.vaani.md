# RNNoise in Vaani

Source: https://github.com/xiph/rnnoise, v0.2, commit
`904a876dce1f9ab8860c0a5000ed151f9f6eef58`. BSD-style license in COPYING.
Only inference sources/headers are included, without training tools or examples.
No runtime downloads or remote audio processing.

The full upstream model is bundled as `Sources/VaaniCore/Resources/rnnoise-model.bin`.
Model archive: https://media.xiph.org/rnnoise/models/rnnoise_data-0b50c45.tar.gz
Archive SHA256: `4ac81c5c0884ec4bd5907026aaae16209b7b76cd9d7f71af582094a2f98f4b43`.
Binary SHA256: `35da861b090c25df53ba7f258b1ea55b1ea36d0c9063d9495bc145ada945c90e`.

To regenerate the binary on little-endian macOS, extract that verified archive
into the pinned upstream checkout, then run:

```
clang -O2 -DDUMP_BINARY_WEIGHTS -Iinclude -Isrc src/write_weights.c -o dump_weights
./dump_weights
```

The resulting `weights_blob.bin` is the bundled model. macOS arm64 and x86_64
are both little-endian. To avoid vendoring 29 MB of generated numeric C literals,
`src/rnnoise_data.c` contains the upstream initializer with all blocks delimited by
`#ifndef USE_WEIGHTS_FILE` and `#endif /* USE_WEIGHTS_FILE */` removed. The build
defines USE_WEIGHTS_FILE and loads the bundled binary explicitly. Remaining
upstream inference code is unmodified except for the ARM/scalar vector headers:
the absent Opus `os_support.h` include and `OPUS_CLEAR` use RNNoise's equivalent
`common.h` and `RNN_CLEAR`. RNNoise expects 480 float samples in
PCM16 amplitude units per 10 ms frame at 48 kHz.

COPYING is also included in the packaged macOS app under Resources/Licenses.
