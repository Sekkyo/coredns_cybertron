#!/bin/bash
set -euo pipefail

# Build script for CoreDNS Cybertron
# Builds multi-platform Docker images with omada and blocker plugins

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="${IMAGE_NAME:-sekkyo/coredns_cybertron}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

cd "$PROJECT_DIR"

echo "Building CoreDNS Cybertron..."
echo "  Image: $IMAGE_NAME:$IMAGE_TAG"
echo "  Platforms: $PLATFORMS"
echo ""

# Check if buildx is available
if ! docker buildx version > /dev/null 2>&1; then
    echo "ERROR: docker buildx is not available" >&2
    echo "Please install Docker Buildx to build multi-platform images" >&2
    exit 1
fi

# Create builder if it doesn't exist
if ! docker buildx inspect cybertron-builder > /dev/null 2>&1; then
    echo "Creating buildx builder 'cybertron-builder'..."
    docker buildx create --name cybertron-builder --use
fi

echo "Using builder: cybertron-builder"
docker buildx use cybertron-builder

# Build the image
echo "Building image..."
docker buildx build \
    --platform "$PLATFORMS" \
    --tag "$IMAGE_NAME:$IMAGE_TAG" \
    --load \
    .

echo ""
echo "Build complete!"
echo ""
echo "Verify plugins are included:"
docker run --rm "$IMAGE_NAME:$IMAGE_TAG" -plugins | grep -E "(omada|blocker)"
echo ""
echo "To push to registry:"
echo "  docker buildx build --platform $PLATFORMS --tag $IMAGE_NAME:$IMAGE_TAG --push ."
