# Version Bumper

This bumps the version in Python, Rust, npm/Bun, and Gradle projects so that you don't need to create new commits just to bump the number before doing a tag release.

The action logic lives in testable shell scripts under `scripts/`, and local regression tests live under `tests/`.

## Local Verification

```bash
sudo apt-get update && sudo apt-get install -y jq
bash tests/run.sh
```

## Examples

```
name: Deploy NPM

on:
  workflow_dispatch:
  release:
    types:
      - published

jobs:
  npm:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
          fetch-depth: 1

      # Replace reedyuk/npm-version with keloran/version-bump
      - uses: keloran/version-bump@v1
        # No inputs needed - auto-extracts tag and doesn't commit by default

      - uses: actions/setup-node@v4
        with:
          node-version: "20.x"
          registry-url: "https://registry.npmjs.org"

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: 1.3.11

      - run: bun install

      - name: Rollup
        run: bun run build

      - name: NPM
        run: npm publish --no-git-checks
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

```
name: Deploy Rust Crate

on:
  workflow_dispatch:
  release:
    types:
      - published

jobs:
  cargo:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
          fetch-depth: 1

      - uses: keloran/version-bump@v1
        # Updates Cargo.toml version

      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable

      - name: Build
        run: cargo build --release

      - name: Publish to crates.io
        run: cargo publish --no-verify
        env:
          CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_TOKEN }}
```

```
name: Deploy Python Package

on:
  workflow_dispatch:
  release:
    types:
      - published

jobs:
  pypi:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
          fetch-depth: 1

      - uses: keloran/version-bump@v1
        # Updates setup.py or pyproject.toml version

      - uses: actions/setup-python@v4
        with:
          python-version: '3.x'

      - name: Install dependencies
        run: |
          pip install build twine

      - name: Build package
        run: python -m build

      - name: Publish to PyPI
        run: twine upload dist/*
        env:
          TWINE_USERNAME: __token__
          TWINE_PASSWORD: ${{ secrets.PYPI_TOKEN }}
```

```
name: Deploy Android Library

on:
  workflow_dispatch:
  release:
    types:
      - published

jobs:
  maven:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
          fetch-depth: 1

      - uses: keloran/version-bump@v1
        # Updates build.gradle or build.gradle.kts version

      - uses: actions/setup-java@v3
        with:
          java-version: '11'
          distribution: 'temurin'

      - name: Build
        run: ./gradlew build

      - name: Publish to Maven Central
        run: ./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository
        env:
          OSSRH_USERNAME: ${{ secrets.OSSRH_USERNAME }}
          OSSRH_PASSWORD: ${{ secrets.OSSRH_PASSWORD }}
          SIGNING_KEY_ID: ${{ secrets.SIGNING_KEY_ID }}
          SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
          SIGNING_SECRET_KEY_RING_FILE: ${{ secrets.SIGNING_SECRET_KEY_RING_FILE }}
```


