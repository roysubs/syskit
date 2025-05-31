#!/bin/bash
# Author: Roy Wiseman 2025-05

IMAGE_NAME="jgoerzen/vintage-computing"

# --- Check for Docker installation ---
if ! command -v docker &> /dev/null
then
    echo "Error: Docker is not installed or not in your PATH."
    echo "Please install Docker to run this script and the image."
    exit 1
fi

# --- Check if the image exists locally ---
echo "Checking for local image: $IMAGE_NAME..."
if docker images --filter "reference=$IMAGE_NAME" --format "{{.ID}}" | grep -q .; then
    echo "Image '$IMAGE_NAME' found locally."
    IMAGE_EXISTS=true
else
    echo "Image '$IMAGE_NAME' not found locally."
    IMAGE_EXISTS=false
fi

# --- Get information about the image (description and size estimate) ---
# Note: Getting the *exact* download size before pulling can be complex,
# as it depends on already existing layers. We'll provide a general idea
# and rely on 'docker pull' showing progress if not local.

# Attempt to get size if image is local
if [ "$IMAGE_EXISTS" = true ]; then
    IMAGE_SIZE=$(docker inspect "$IMAGE_NAME" --format "{{.Size}}")
    # Convert size to human-readable format (approximate)
    if (( IMAGE_SIZE > 1000000000 )); then
        HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000000000" | bc)GB
    elif (( IMAGE_SIZE > 1000000 )); then
        HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000000" | bc)MB
    else
        HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000" | bc)KB
    fi
    echo "Local image size: $HUMAN_SIZE"
fi

# --- Describe the image ---
echo ""
echo "--- Image Information ---"
echo ""
echo "Image Name: $IMAGE_NAME"
echo ""
echo "Description: This image provides a vintage computing environment based on Debian."
echo "It includes a collection of classic text adventure games (like Colossal Cave Adventure and Zork),"
echo "BSD games, vintage command-line tools, and emulators for old systems (like PDP-11)."
echo "It's designed for interacting purely through the terminal."
echo ""

# --- Handle image not being installed ---
if [ "$IMAGE_EXISTS" = false ]; then
    echo "--- Download Required ---"
    echo "The image '$IMAGE_NAME' is not installed locally."
    echo "Downloading this image will require fetching its layers from Docker Hub."
    echo "The total download size can be significant (potentially several hundred MB or more,"
    echo "depending on the base image and included software)."
    echo ""
    read -r -p "Do you want to download the image '$IMAGE_NAME' now? (y/N) " response
    response=${response,,} # Convert response to lowercase

    if [[ "$response" =~ ^(yes|y)$ ]]; then
        echo "Attempting to download image. Progress will be shown below:"
        echo "----------------------------------------------------------"
        if docker pull "$IMAGE_NAME"; then
            echo "----------------------------------------------------------"
            echo "Download complete."
            IMAGE_EXISTS=true # Update flag
            # Re-check size now that it's downloaded
            IMAGE_SIZE=$(docker inspect "$IMAGE_NAME" --format "{{.Size}}")
             if (( IMAGE_SIZE > 1000000000 )); then
                HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000000000" | bc)GB
            elif (( IMAGE_SIZE > 1000000 )); then
                HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000000" | bc)MB
            else
                HUMAN_SIZE=$(echo "scale=1; $IMAGE_SIZE / 1000" | bc)KB
            fi
            echo "Downloaded image size: $HUMAN_SIZE"
        else
            echo "----------------------------------------------------------"
            echo "Error: Failed to download image '$IMAGE_NAME'."
            exit 1
        fi # Corrected: changed 'end' to 'fi'
    else
        echo "Download cancelled by user. Exiting."
        exit 0 # Exit gracefully if user cancels
    fi
fi # Corrected: changed 'end' to 'fi'

# --- Output Usage Information ---
if [ "$IMAGE_EXISTS" = true ]; then
    echo ""
    echo ""
    echo ""
    echo ""
    echo "Once the container starts, you will be presented with a bash shell prompt inside the vintage environment."
    echo "From there, you can execute the various included programs and games."
    echo ""
    echo "Examples of commands you might use inside the container:"
    echo "  adventure       - Start Colossal Cave Adventure"
    echo "  zork            - Start Zork (multiple versions available, might need to specify)"
    echo "  usrgames list   - List available games from the bsdgames package"
    echo "  fortune         - Display a random fortune"
    echo "  figlet hello    - Print 'hello' in large text"
    echo "  vint pdp11-2bsd - Start a PDP-11 emulator with 2BSD Unix"
    echo ""
    echo "Type 'exit' or press Ctrl+D to leave the container when you are finished."
    echo "Note: if stuck, use the Ctrl + P, Ctrl + Q sequence to detach from a stuck container."
    echo "This is required as the process is running as PID 1 (login process or systemd managing it)."
    echo
    echo "--- Run and Use the Image ---"
    echo "To run the '$IMAGE_NAME' container and start an interactive bash session inside it, use:"
    echo "  docker run -it --rm --priveleged $IMAGE_NAME /bin/bash"
    echo
    echo "  docker run: Creates and starts a new container."
    echo "  -i (or --interactive): Keeps the standard input open, allowing interaction."
    echo "  -t (or --tty): Allocates a pseudo-TTY, essential for a proper terminal session."
    echo "  --rm: Automatically removes the container and its filesystem when you exit."
    echo "  $IMAGE_NAME: The name of the Docker image to run."
    echo
    echo "For more detailed information on the specific contents and usage of this image,"
    echo "please refer to the official documentation for 'jgoerzen/vintage-computing' on Docker Hub or GitHub."
    echo
    echo "Script finished. You can now run the 'docker run' command shown above to start the container."
fi

exit 0
