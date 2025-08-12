FROM cgr.dev/chainguard-private/tritonserver-vllm-backend:latest-dev AS vllm
USER 0

#Add additional apks if needed
#RUN apk update && apk add --no-cache ca-certificates gnupg curl jq google-cloud-sdk

# Prefer Triton’s venv
ENV PATH=/opt/tritonserver/venv/bin:$PATH \
    PYTHONPATH=/opt/tritonserver/venv/lib/python3.10/site-packages:$PYTHONPATH \
    PYTHONNOUSERSITE=1

# Ensure pip in venv
RUN /opt/tritonserver/venv/bin/python3 -m ensurepip --upgrade || true

# Ensure venv dependencies match the underlying OS for Chainguard
RUN /opt/tritonserver/venv/bin/python3 -m pip install --no-cache-dir \
    uvicorn rich \
    vllm==0.9.2 

## If running qwen3-8b with bnb-4bit quantization also add this package
    #"bitsandbytes>=0.45.0"

WORKDIR /work
COPY main.py ./main.py
COPY examplegpt ./example.gpt
COPY ./entrypoints/example_entrypoint.sh /work/entrypoint.sh
RUN chmod +x /work/entrypoint.sh

ENV VLLM_USE_V1=1
ENTRYPOINT ["/work/entrypoint.sh"]
