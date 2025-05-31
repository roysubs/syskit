# Choose a base image with a compatible GLIBC.
# Ubuntu 24.04 LTS (Noble Numbat) should have GLIBC >= 2.39
FROM ubuntu:24.04

# Install prerequisites for downloading and extracting
# Using DEBIAN_FRONTEND=noninteractive to prevent potential interactive prompts
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl \
        tar \
        gzip \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Variables for onefetch version and download
# You can update this ARG if a newer onefetch version is released
ARG ONEFETCH_VERSION=2.24.0
ARG ONEFETCH_ASSET_PATTERN="onefetch-linux.tar.gz"
ARG PROGRAM_NAME="onefetch"

# Download and install onefetch
RUN curl -Lo "/tmp/${ONEFETCH_ASSET_PATTERN}" \
         "https://github.com/o2sh/onefetch/releases/download/${ONEFETCH_VERSION}/${ONEFETCH_ASSET_PATTERN}" && \
    tar -xzf "/tmp/${ONEFETCH_ASSET_PATTERN}" -C /usr/local/bin/ && \
    chmod +x "/usr/local/bin/${PROGRAM_NAME}" && \
    rm "/tmp/${ONEFETCH_ASSET_PATTERN}"

# Set a working directory (optional, can be overridden)
WORKDIR /mnt/repo

# Default command (can be overridden by the docker run command)
ENTRYPOINT ["onefetch"]
CMD []
# CMD ["--help"]   # Could hardcode some command options if required
