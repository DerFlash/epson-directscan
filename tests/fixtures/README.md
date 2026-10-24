# Synthetic JPEG fixture

`tiny-white.jpg` is a locally generated 2 × 2 pixel white image. It contains no
scanner output, customer content, personal information or third-party artwork.

Generation used Python's standard `struct` and `zlib` modules to write a PNG with
a 2 × 2 RGB IHDR, two unfiltered white pixel rows, an IDAT chunk and IEND, with
standard CRCs. macOS then converted that synthetic PNG using:

```sh
sips -s format jpeg /tmp/scansmart-fixture.png --out tests/fixtures/tiny-white.jpg
```

The fixture is provided under the project's MIT license, like the test sources.
Negative JPEG cases are derived in memory by the runtime tests: SOI-only bytes,
the first half of this image, marker-wrapped garbage and plain non-image bytes.
