#!/bin/bash
# Author: Roy Wiseman 2025-02

# Script to run onefetch inside a Docker container against a local repository.

# Name of the Docker image built from Dockerfile.onefetch
DOCKER_IMAGE_NAME="onefetch-runner"

# --- Helper Functions ---
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# --- Main Logic ---

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    print_error "Docker command not found. Please install Docker."
fi
if ! docker info > /dev/null 2>&1; then
    print_error "Docker daemon doesn't seem to be running. Please start Docker."
fi

# Determine the target repository directory
# Default to current directory, or use the first argument if provided
TARGET_REPO_PATH="${1:-.}"

# Convert to absolute path
if [[ "$TARGET_REPO_PATH" != /* ]]; then
    TARGET_REPO_PATH="$(pwd)/${TARGET_REPO_PATH}"
fi

if [ ! -d "${TARGET_REPO_PATH}/.git" ]; then
    print_error "Target directory '${TARGET_REPO_PATH}' does not appear to be a Git repository (missing .git folder)."
fi

print_info "Running onefetch in container for repository: ${TARGET_REPO_PATH}"
print_info "Using Docker image: ${DOCKER_IMAGE_NAME}"

# Any additional arguments passed to this script (after the optional repo path)
# will be passed to the onefetch command inside the container.
shift # Remove the first argument (repo path) if it was given, otherwise no-op if no args.
ONEFETCH_ARGS="$@"

# Run onefetch in a temporary container
# --rm: Automatically remove the container when it exits.
# -i: Keep STDIN open even if not attached.
# -t: Allocate a pseudo-TTY (important for interactive output and colors).
# -v "${TARGET_REPO_PATH}":/mnt/repo:ro : Mount the host repo read-only into /mnt/repo in the container.
# -w /mnt/repo : Set the working directory inside the container.
# ${DOCKER_IMAGE_NAME} : The image to use.
# onefetch ${ONEFETCH_ARGS} : The command to run inside the container.
#                             The ENTRYPOINT in the Dockerfile is "onefetch",
#                             so we just provide arguments here.
#                             If ENTRYPOINT was not set, we'd use "onefetch ${ONEFETCH_ARGS}".

docker run --rm -it \
    -v "${TARGET_REPO_PATH}":/mnt/repo:ro \
    -w /mnt/repo \
    "${DOCKER_IMAGE_NAME}" ${ONEFETCH_ARGS}

if [ $? -ne 0 ]; then
    print_error "onefetch command in container failed."
else
    print_info "onefetch command completed successfully."
fi
