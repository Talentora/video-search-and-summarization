#!/bin/bash

echo "Starting VSS in CPU/API-only mode..."

# Set environment for CPU-only operation
export CUDA_VISIBLE_DEVICES=""
export NUM_GPUS=0
export VLM_MODEL_TO_USE=openai-compat
export FORCE_CPU_ONLY=true

# Set Python path to include the VSS source directory (use modified version if available)
if [ -d "/opt/nvidia/via-modified" ]; then
    echo "Using modified VSS source code with CUDA profiler fix..."
    export PYTHONPATH="/opt/nvidia/via-modified:/opt/nvidia/via-modified/src:$PYTHONPATH"
    VSS_SRC_DIR="/opt/nvidia/via-modified/src"
else
    echo "Using default VSS source code..."
    export PYTHONPATH="/opt/nvidia/via:/opt/nvidia/via/via-engine:$PYTHONPATH"
    VSS_SRC_DIR="/opt/nvidia/via/via-engine"
fi

# Set default ports if not specified
export BACKEND_PORT=${BACKEND_PORT:-8100}
export FRONTEND_PORT=${FRONTEND_PORT:-9100}

# Create required directories
mkdir -p /tmp/assets
mkdir -p /tmp/via-logs

# Check directory structure
echo "Directory structure:"
ls -la /opt/nvidia/via/via-engine/
echo "Looking for Python files:"
find /opt/nvidia/via/via-engine -name "*.py" | head -10

# Start VSS directly with CPU-only parameters
cd /opt/nvidia/via

# Build command line arguments based on environment variables
VIA_ARGS="--asset-dir /tmp/assets --port $BACKEND_PORT --host 0.0.0.0 --vlm-model-type openai-compat --num-gpus 0"

# Add VLM processing parameters if set
if [ ! -z "${VLM_DEFAULT_NUM_FRAMES_PER_CHUNK}" ]; then
    VIA_ARGS="$VIA_ARGS --num-frames-per-chunk ${VLM_DEFAULT_NUM_FRAMES_PER_CHUNK}"
fi

# VLM_INPUT_WIDTH and VLM_INPUT_HEIGHT are environment variables read by the code directly
# No need to pass them as command-line arguments

# Add CV pipeline flag if disabled
if [ "${DISABLE_CV_PIPELINE:-true}" = "true" ]; then
    VIA_ARGS="$VIA_ARGS --disable-cv-pipeline"
fi

# Add guardrails flag if disabled
if [ "${DISABLE_GUARDRAILS:-false}" = "true" ]; then
    VIA_ARGS="$VIA_ARGS --disable-guardrails"
fi

# Add CA-RAG flag if disabled
if [ "${DISABLE_CA_RAG:-false}" = "true" ]; then
    VIA_ARGS="$VIA_ARGS --disable-ca-rag"
fi

echo "Starting VSS backend server with args: $VIA_ARGS"
python3 $VSS_SRC_DIR/via_server.py $VIA_ARGS &

# Wait for backend to be ready
echo "Waiting for backend to be ready..."
while true; do
    response=$(curl -s "http://localhost:$BACKEND_PORT/health/ready")
    if [ $? -eq 0 ]; then
        echo "Backend is ready!"
        break
    fi
    sleep 2
done

# Start frontend demo client
echo "Starting VSS frontend client..."
python3 $VSS_SRC_DIR/via_demo_client.py \
  --backend http://localhost:$BACKEND_PORT \
  --port $FRONTEND_PORT \
  --host 0.0.0.0 \
  --examples-streams-directory /opt/nvidia/via/streams &

# Wait for frontend to be ready
echo "Waiting for frontend to be ready..."
while true; do
    response=$(curl -s "http://localhost:$FRONTEND_PORT/")
    if [ $? -eq 0 ]; then
        echo "Frontend is ready!"
        break
    fi
    sleep 2
done

echo "***********************************************************"
echo "VSS Server started successfully!"
echo "Backend API: http://0.0.0.0:$BACKEND_PORT"
echo "Frontend UI: http://0.0.0.0:$FRONTEND_PORT"
echo "***********************************************************"

# Keep the script running
wait 