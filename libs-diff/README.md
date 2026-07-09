# Libraries diff

Extracts two Python sdists and diffs their contents. Can either take two local tarballs or `--fetch` a base + remediated version from `libraries.cgr.dev` first.

## Usage

```
./libs-diff.sh [options] <sdist1.tar.gz> <sdist2.tar.gz>
./libs-diff.sh [options] --fetch <package> <version> <suffix>
```

## Options

- `-d`, `--diff` — show full line-level unified diffs (default is a brief file-by-file summary).
- `-o`, `--output <file>` — write the unified diff to `<file>` (implies `-d`).
- `--fetch <pkg> <version> <suffix>` — download the base sdist and the remediated sdist (e.g. `cgr.1`) from `libraries.cgr.dev`, then diff them. Requires `CG_PYTHON_USER` and `CG_PYTHON_PASS` to be exported.

`PKG-INFO` and `*.egg-info` are excluded from the diff.

## Example

```
# download sdists and run diff
./libs-diff.sh -o out.patch --fetch onnx 1.18.0 cgr.1

# run diff on two downloaded sdists
./libs-diff.sh onnx-1.18.0.tar.gz onnx-1.18.0+cgr.1.tar.gz

# run diff with detailed output
./libs-diff.sh -d onnx-1.18.0.tar.gz onnx-1.18.0+cgr.1.tar.gz
```