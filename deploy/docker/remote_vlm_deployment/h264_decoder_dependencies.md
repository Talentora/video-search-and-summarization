# H.264 Decoder Dependencies for VSS CPU-Only Mode

## Essential Dependencies for Video Processing

This list contains all the dependencies needed to get H.264 video decoding working in CPU-only mode for VSS (Video Search and Summarization).

### Core Multimedia Packages
```bash
# Primary codec package (this is the key one that fixed our issue)
ubuntu-restricted-extras  # Meta-package containing multimedia codecs including libavcodec-extra60

# Audio/Video codec libraries
libjack0                  # Audio interface library
libvpx9                   # VP8/VP9 codec
libzvbi0t64              # VBI decoding library  
libmp3lame0              # MP3 encoding library
libx265-199              # H.265 codec
libunibreak5             # Unicode line breaking library
libmpg123-0t64           # MP3 decoding library
```

### Installation Commands Used
```bash
# Install core codec meta-package
sudo apt-get update
sudo apt-get install -y ubuntu-restricted-extras

# Install additional audio/video libraries
sudo apt-get install -y libjack0 libvpx9 libzvbi0t64 libmp3lame0 libx265-199

# Install Unicode and MP3 libraries (critical for GStreamer plugin loading)
sudo apt-get install -y libunibreak5 libmpg123-0t64

# Force reinstall if library files are missing
sudo apt-get install --reinstall -y libunibreak5 libmpg123-0t64

# Refresh library cache
sudo ldconfig

# Clear GStreamer plugin cache
rm -rf ~/.cache/gstreamer-1.0
```

### Key Library Files Required
```
/usr/lib/x86_64-linux-gnu/libunibreak.so.5
/usr/lib/x86_64-linux-gnu/libmpg123.so.0
/usr/lib/x86_64-linux-gnu/libgstlibav.so (GStreamer libav plugin)
```

### Verification Commands
```bash
# Test H.264 decoder availability
gst-inspect-1.0 avdec_h264

# Test complete pipeline
gst-launch-1.0 -v videotestsrc num-buffers=10 ! x264enc ! h264parse ! avdec_h264 ! videoconvert ! fakesink

# Test real video file
gst-launch-1.0 -v filesrc location=test.mp4 ! decodebin ! videoconvert ! fakesink
```

### Critical Success Indicators
- `avdec_h264` decoder shows "Factory Details: Rank primary (256)"
- GStreamer pipeline completes without "No such element" errors
- VSS can extract JPEG frames from uploaded videos
- Video processing progresses beyond 0%

### Environment Variables Added to .env
```bash
# Essential for video frame processing
VLM_DEFAULT_NUM_FRAMES_PER_CHUNK=8
VLM_INPUT_WIDTH=224
VLM_INPUT_HEIGHT=224
```

## Dockerfile Integration
To avoid manual setup, add these dependencies to the Dockerfile:

```dockerfile
# Add multimedia codec dependencies
RUN apt-get update && apt-get install -y \
    ubuntu-restricted-extras \
    libjack0 \
    libvpx9 \
    libzvbi0t64 \
    libmp3lame0 \
    libx265-199 \
    libunibreak5 \
    libmpg123-0t64 \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig
```

## Notes
- The `ubuntu-restricted-extras` package was the key breakthrough - it contains `libavcodec-extra60` and other essential multimedia codecs
- Without `libunibreak5` and `libmpg123-0t64`, the GStreamer libav plugin fails to load
- These dependencies enable CPU-only H.264 decoding without requiring GPU or CUDA
- The exact package names may vary slightly between Ubuntu versions 