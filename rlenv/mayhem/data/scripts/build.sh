#!/bin/bash
set -euo pipefail

# RLENV Build Script
# This script rebuilds the application from source located at /rlenv/source/picoc/
#
# Original image: ghcr.io/mayhemheroes/picoc:master
# Git revision: c34a3d5d4c983df066c8602c558b3751776a139c

# ============================================================================
# REQUIRED: Change to Source Directory
# ============================================================================
cd /rlenv/source/picoc/

# ============================================================================
# Clean Previous Build
# ============================================================================
make clean 2>/dev/null || rm -f picoc *.o platform/*.o cstdlib/*.o

# ============================================================================
# Build Application
# ============================================================================
make -j8

# ============================================================================
# Copy Artifact to Expected Location
# ============================================================================
cat picoc > /picoc
chmod 777 /picoc 2>/dev/null || true

# ============================================================================
# REQUIRED: Verify Build Succeeded
# ============================================================================
if [ ! -f /picoc ]; then
    echo "Error: Build artifact not found at /picoc"
    exit 1
fi

echo "Build completed successfully: /picoc"
