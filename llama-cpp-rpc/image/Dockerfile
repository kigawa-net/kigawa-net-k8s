# llama.cpp (llama-server + rpc-server) CUDA image for RPC verification.
# The official llama.cpp images do not ship rpc-server, so build it here.
ARG CUDA_VERSION=12.4.1
ARG UBUNTU_VERSION=22.04

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS build

ARG LLAMA_CPP_REF=b12199
# 80 = A100/Ampere datacenter, 86 = RTX 3060 (Ampere). Keep short for build time.
ARG CUDA_ARCHS="80;86"

RUN apt-get update && apt-get install -y --no-install-recommends \
      git cmake build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch ${LLAMA_CPP_REF} https://github.com/ggml-org/llama.cpp.git .

# libcuda.so is only needed at link time; use the toolkit stub (real one comes from the host driver).
RUN cmake -B build \
      -DGGML_CUDA=ON \
      -DGGML_RPC=ON \
      -DGGML_NATIVE=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_CURL=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs -L/usr/local/cuda/lib64/stubs" \
    && cmake --build build --config Release -j"$(nproc)" --target llama-server rpc-server

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=build /src/build/bin/rpc-server /usr/local/bin/rpc-server
# Stub libcuda, used only for GPU-less smoke tests (--help) via LD_LIBRARY_PATH.
# Not on the default library path, so the host driver's libcuda is used at runtime.
COPY --from=build /usr/local/cuda/lib64/stubs/libcuda.so /opt/cuda-stubs/libcuda.so.1

EXPOSE 8080 50052
