# Example Project

This is a minimal example of a vllm model running on the tritonserver-vllm-backend Chainguard image, when a virtual environment is in use. 

```
.
├── Dockerfile
├── main.py
├── examplegpt/           # copied into the image as ./example.gpt
│   └── __init__.py
└── entrypoints/
    └── example_entrypoint.sh -> copied to /work/entrypoint.sh
```

In order for a functioning entrypoint in the main.py execution, vllm=0.9.2 must be installed in the venv

```
# Prefer Triton’s venv
ENV PATH=/opt/tritonserver/venv/bin:$PATH \
    PYTHONPATH=/opt/tritonserver/venv/lib/python3.10/site-packages:$PYTHONPATH \
    PYTHONNOUSERSITE=1

# Ensure pip in venv
RUN /opt/tritonserver/venv/bin/python3 -m ensurepip --upgrade || true

# Ensure venv dependencies match the underlying OS for Chainguard
RUN /opt/tritonserver/venv/bin/python3 -m pip install --no-cache-dir \
    vllm==0.9.2 \
```

Installing vllm==0.9.2 matches all of the required dependencies to the Chainguard OS system level versions by including them in the venv with the following versions:

- tritonclient 2.45.0
- triton (openAI compiler) 3.3.0
- numpy >=2 (2.2.6)
- torch >= 2.6 (2.7.0+cu126)

**Chainguard's default versions for OS-level dependencies:**

- tritonclient 2.45.0
- triton (openAI compiler) 3.3.1
- numpy >=2 (2.2.6)
- torch >= 2.6 ( 2.6.0+cu124)


## Build (amd64)
```bash
docker buildx build --platform linux/amd64 -t example-vllm:test .
```

## Run
```bash
docker run --rm --platform linux/amd64 example-vllm:test --demo
```

The main.py script will run through preflight checks of the expected modules to ensure there are no errors. GPU warnings can be ignored if running on a localmachine (mac) or other non-GPU supported