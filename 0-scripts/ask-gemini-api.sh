#!/bin/bash
# Author: Roy Wiseman 2025-05

# Get a Google Gemini API Key:
# Go to Google AI Studio https://aistudio.google.com/ (or the Google Cloud Console if you are using Vertex AI Gemini models,
# but this script is for the Google AI Generative Language API).
# Create an API key.
# Enable the API: Ensure the "Generative Language API" (sometimes referred to as Google AI Ggenerative Language API) is enabled for your project associated with the API key.
# Install jq: This is a command-line JSON processor, essential for parsing the API's response.
# On Debian/Ubuntu: sudo apt update && sudo apt install jq
# On macOS (using Homebrew): brew install jq
# On other systems, search for "install jq [your OS]".
# Set your Google API Key: The script expects your API key to be in an environment variable named GOOGLE_API_KEY. 
# Do not hardcode your API key into the script. Set it in your shell session like this:
#     export GOOGLE_KEY="your_actual_google_key_here"

# --- Configuration & Prerequisites ---

# 1. Check for Google API Key
if [ -z "$GOOGLE_KEY" ]; then
  echo "Error: The GOOGLE_KEY environment variable is not set." >&2
  echo "Please set it before running the script:" >&2
  echo "  export GOOGLE_KEY='your_actual_google_api_key_here'" >&2
  exit 1
fi

# 2. Check for input question
if [ -z "$1" ]; then
  echo "Usage: ${0##*/} \"Your question to Gemini\"" >&2
  echo "Example: ${0##*/} \"What are the main moons of Jupiter?\"" >&2
  exit 1
fi
USER_PROMPT="$1"

# 3. Check for jq (JSON processor)
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. Please install jq to parse the API response." >&2
  echo "See script comments for installation instructions." >&2
  exit 1
fi

# --- API Call ---

# Using gemini-1.5-flash-latest for a balance of speed and capability.
# You can also use "gemini-1.5-pro-latest" or other available models.
MODEL_NAME="gemini-1.5-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL_NAME}:generateContent?key=${GOOGLE_KEY}"
REQUEST_TIMEOUT_SECONDS=60 # Set a timeout for the API call

# Inform the user that the script is working
echo "Asking Gemini (using $MODEL_NAME)... please wait." >&2

# Construct the JSON payload
# For Gemini, the structure is different from OpenAI's.
# We're sending a single user prompt.
json_payload=$(jq -n \
                  --arg prompt "$USER_PROMPT" \
                  '{contents: [{"role": "user", parts: [{text: $prompt}]}]}')
                  # Optional: Add generationConfig for temperature, maxOutputTokens, etc.
                  # Example: '{contents: [...], generationConfig: {"temperature": 0.7, "maxOutputTokens": 1024}}')

# Make the API call using curl
# -s: silent mode (no progress meter)
# -S: show error message on explicit error, used with -s
# --max-time: maximum time in seconds that you allow the whole operation to take
api_response=$(curl -s -S -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  --max-time "$REQUEST_TIMEOUT_SECONDS" \
  -d "$json_payload")

# --- Response Handling ---

# Check if curl command itself failed (e.g., network issue, timeout before response)
if [ $? -ne 0 ]; then
  echo "Error: curl command failed. This could be a network issue, a timeout ($REQUEST_TIMEOUT_SECONDS seconds), or an incorrect API endpoint/key setup." >&2
  if [ -n "$api_response" ]; then
    echo "Partial response/error from curl: $api_response" >&2
  fi
  exit 1
fi

# Check for API errors in the JSON response
# Google API errors typically have an "error" object with a "message" field.
api_error_message=$(echo "$api_response" | jq -r '.error.message // empty')

if [ -n "$api_error_message" ]; then
  echo "API Error: $api_error_message" >&2
  # api_error_status=$(echo "$api_response" | jq -r '.error.status // empty')
  # api_error_code=$(echo "$api_response" | jq -r '.error.code // empty')
  # if [ -n "$api_error_status" ]; then echo "Status: $api_error_status" >&2; fi
  # if [ -n "$api_error_code" ]; then echo "Code: $api_error_code" >&2; fi
  # echo "Full API error response: $api_response" >&2
  exit 1
fi

# Extract the assistant's message content
# The response structure is usually candidates[0].content.parts[0].text
# Using // empty for robustness in case the path doesn't exist
assistant_message=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text // empty')

if [ -z "$assistant_message" ]; then
  # Sometimes, if the model refuses to answer (e.g. safety settings),
  # candidates might be empty or parts might be missing.
  # Or the model might have finished for a reason like "SAFETY"
  finish_reason=$(echo "$api_response" | jq -r '.candidates[0].finishReason // empty')
  safety_ratings_problem=$(echo "$api_response" | jq -r '.candidates[0].safetyRatings[] | select(.probability != "NEGLIGIBLE" and .probability != "LOW") | .category' | head -n 1)

  echo "Error: Could not extract a message from the API response." >&2
  if [ -n "$finish_reason" ] && [ "$finish_reason" != "STOP" ]; then
    echo "The model finished due to: $finish_reason" >&2
  fi
  if [ -n "$safety_ratings_problem" ]; then
    echo "Potential safety concern flagged for category: $safety_ratings_problem" >&2
  fi
  echo "This might be due to an unexpected response format, an issue with your API key/quota, content policy, or the model not returning text content." >&2
  echo "Full API response for debugging:" >&2
  echo "$api_response" >&2
  exit 1
fi

# Output the assistant's message (this is the main output)
echo "$assistant_message"
