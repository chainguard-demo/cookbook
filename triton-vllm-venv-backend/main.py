import os, sys, traceback, importlib.metadata as im


if os.getenv("VLLM_PREFLIGHT", "1") == "1":  # set to 0 to skip
    print("=== vLLM/Torch preflight ===")
    # Show interpreter & package sources
    print("exe:", sys.executable)
    try:
        import torch
        print("torch:", torch.__version__, "from:", torch.__file__)
    except Exception as e:
        print("torch: FAIL ->", e); sys.exit(1)

    try:
        import numpy
        print("numpy:", numpy.__version__)
    except Exception as e:
        print("numpy: FAIL ->", e); sys.exit(1)

    try:
        import triton  # OpenAI Triton compiler
        print("triton(OpenAI):", im.version("triton"))
    except Exception as e:
        print("triton(OpenAI): FAIL ->", e)

    # 1) Does TorchInductor import (often triggers AttrsDescriptor path)?
    try:
        import torch._inductor.runtime.hints as H  # noqa
        print("torch._inductor.runtime.hints: OK")
    except Exception as e:
        print("torch._inductor.runtime.hints: FAIL ->", e)
        traceback.print_exc()
        sys.exit(2)

    # 2) Does the FP8/QUARK utils import (where list[int] sometimes hits)?
    try:
        from vllm.model_executor.layers.quantization.utils import fp8_utils  # noqa
        print("vllm fp8_utils import: OK")
    except Exception as e:
        print("vllm fp8_utils import: FAIL ->", e)
        traceback.print_exc()
        # Not fatal if you’re using BnB, but surface it:
        sys.exit(3)

    # 3) Finally, does vLLM engine import?
    try:
        from vllm.engine.async_llm_engine import AsyncLLMEngine  # noqa
        print("AsyncLLMEngine import: OK")
    except Exception as e:
        print("AsyncLLMEngine import: FAIL ->", e)
        traceback.print_exc()
        sys.exit(4)

    print("=== preflight passed ===")
