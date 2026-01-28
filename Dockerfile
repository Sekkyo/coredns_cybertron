FROM golang:1.24-bookworm AS builder
ARG TARGETOS TARGETARCH
ARG COREDNS_VERSION=v1.12.3

WORKDIR /workspace

# Clone CoreDNS
RUN git clone --depth 1 --branch ${COREDNS_VERSION} https://github.com/coredns/coredns.git /coredns

# Clone plugins
RUN git clone https://github.com/dougbw/coredns_omada.git /coredns_omada && \
    git clone https://github.com/icyflame/blocker.git /blocker

# Configure plugin.cfg with execution order: metadata -> prometheus -> log -> omada -> blocker -> forward
# This allows local devices (omada) to bypass ad-blocking (blocker)
# Only add our custom plugins (omada and blocker) between log and forward
WORKDIR /coredns
RUN sed -i '/^log:log$/a omada:github.com/dougbw/coredns_omada' plugin.cfg && \
    sed -i '/^omada:github.com\/dougbw\/coredns_omada$/a blocker:blocker' plugin.cfg

# Create symlink for blocker plugin (uses local reference approach)
RUN ln -s /blocker /coredns/plugin/blocker

# Add omada plugin to go.mod as a required module, then replace with local path
RUN go get github.com/dougbw/coredns_omada@latest && \
    echo "" >> go.mod && \
    echo "replace github.com/dougbw/coredns_omada => /coredns_omada" >> go.mod

# Generate plugin integration code
RUN go generate

# Build CoreDNS with both plugins
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} make

# Verify plugins are included
RUN ./coredns -plugins | grep -E "(omada|blocker)"

# Runtime stage - minimal image
FROM debian:bookworm-slim

# Install CA certificates for HTTPS verification (needed for Omada controller and blocklist downloads)
RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Copy CoreDNS binary
COPY --from=builder /coredns/coredns /usr/local/bin/coredns

# Create directories
RUN mkdir -p /etc/coredns /var/lib/coredns

# Create non-root user
RUN useradd -r -u 1000 -s /bin/false coredns

# Set ownership
RUN chown -R coredns:coredns /etc/coredns /var/lib/coredns

# Switch to non-root user
USER coredns

# Expose DNS ports
EXPOSE 53/udp 53/tcp

WORKDIR /etc/coredns

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["coredns", "-health"]

ENTRYPOINT ["/usr/local/bin/coredns"]
CMD ["-conf", "/etc/coredns/Corefile"]
