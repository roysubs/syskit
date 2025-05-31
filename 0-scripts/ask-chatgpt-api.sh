#!/bin/bash
# Author: Roy Wiseman 2025-05

# Send a question as a command-line argument and outputs the GPT's answer directly to the console.
# Set your OpenAI API Key: The script expects your API key to be in an environment variable named
# OPENAI_KEY. Do not hardcode your API key into the script. Set it in your shell session like this:
#     export OPENAI_KEY="your_actual_key_here"
# This could also be put into ~/.bashrc

# --- Configuration & Prerequisites ---

# 1. Check for OpenAI API Key
if [ -z "$OPENAI_KEY" ]; then
  echo "Error: The OPENAI_KEY environment variable is not set." >&2
  echo "Please set it before running the script:" >&2
  echo "  export OPENAI_KEY='your_actual_api_key_here'" >&2
  exit 1
fi

# 2. Check for input question
if [ -z "$1" ]; then
  echo "Usage: ${0##*/} \"Your question to ChatGPT\"" >&2
  echo "Example: ${0##*/} \"What is the capital of France?\"" >&2
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

API_URL="https://api.openai.com/v1/chat/completions"
# You can change the model if you prefer, e.g., "gpt-4o", "gpt-4-turbo"
MODEL_NAME="gpt-3.5-turbo"
REQUEST_TIMEOUT_SECONDS=60 # Set a timeout for the API call

# Inform the user that the script is working
echo "Asking GPT (using $MODEL_NAME)... please wait." >&2

# Construct the JSON payload using jq to ensure the prompt is correctly escaped
# You could add a system prompt here if needed:
# e.g., messages: [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": $prompt}]
json_payload=$(jq -n \
                  --arg model "$MODEL_NAME" \
                  --arg prompt "$USER_PROMPT" \
                  '{model: $model, messages: [{"role": "user", "content": $prompt}]}')

# Make the API call using curl
# -s: silent mode (no progress meter)
# -S: show error message on explicit error, used with -s
# --max-time: maximum time in seconds that you allow the whole operation to take
api_response=$(curl -s -S -X POST "$API_URL" \
  -H "Authorization: Bearer $OPENAI_KEY" \
  -H "Content-Type: application/json" \
  --max-time "$REQUEST_TIMEOUT_SECONDS" \
  -d "$json_payload")

# --- Response Handling ---

# Check if curl command itself failed (e.g., network issue, timeout before response)
if [ $? -ne 0 ]; then
  echo "Error: curl command failed. This could be a network issue, a timeout ($REQUEST_TIMEOUT_SECONDS seconds), or an incorrect API endpoint." >&2
  # The api_response might be empty or contain partial data if curl failed mid-transfer
  if [ -n "$api_response" ]; then
    echo "Partial response/error from curl: $api_response" >&2
  fi
  exit 1
fi

# Check for API errors in the JSON response (e.g., authentication failure, rate limits)
# The 'jq' command will output 'null' if '.error.message' doesn't exist, which [ -n "$api_error" ] treats as empty.
api_error_message=$(echo "$api_response" | jq -r '.error.message // empty') # Use // empty for robustness

if [ -n "$api_error_message" ]; then
  echo "API Error: $api_error_message" >&2
  # Optionally print the full error response for more details
  # echo "Full API error response: $api_response" >&2
  exit 1
fi

# Extract the assistant's message content
# Use // empty to prevent jq from erroring if the path is missing, and return empty string instead.
assistant_message=$(echo "$api_response" | jq -r '.choices[0].message.content // empty')

if [ -z "$assistant_message" ]; then
  echo "Error: Could not extract a message from the API response." >&2
  echo "This might be due to an unexpected response format, an issue with your API key/quota, or the model not returning content." >&2
  echo "Full API response for debugging:" >&2
  echo "$api_response" >&2
  exit 1
fi

# Output the assistant's message (this is the main output)
echo "$assistant_message"
