# Custom VSS Image with H.264 Decoder Dependencies
# Extends the base NVIDIA VSS image with multimedia codec support for CPU-only operation

FROM nvcr.io/nvidia/blueprint/vss-engine:2.3.1

# Install H.264 decoder dependencies for CPU-only video processing
# These packages enable video decoding without requiring GPU/CUDA
RUN apt-get update && \
    # Accept license for restricted packages
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' | debconf-set-selections && \
    # Install essential multimedia codec packages
    apt-get install -y \
        ubuntu-restricted-extras \
        libjack0 \
        libvpx9 \
        libzvbi0t64 \
        libmp3lame0 \
        libx265-199 \
        libunibreak5 \
        libmpg123-0t64 \
        && \
    # Clean up package cache to reduce image size
    rm -rf /var/lib/apt/lists/* && \
    # Update library cache
    ldconfig && \
    # Clear any existing GStreamer plugin cache
    rm -rf /root/.cache/gstreamer-1.0 || true

# Verify H.264 decoder installation
RUN gst-inspect-1.0 avdec_h264 > /dev/null 2>&1 && \
    echo "H.264 decoder successfully installed" || \
    echo "Warning: H.264 decoder installation may have issues"

# Add metadata
LABEL maintainer="VSS CPU-Only Setup"
LABEL description="VSS Engine with H.264 decoder dependencies for CPU-only operation"
LABEL version="2.3.1-cpu-h264"

# The rest of the image remains the same as the base VSS image
# Entry point and command will be overridden by docker-compose 