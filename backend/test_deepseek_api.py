#!/usr/bin/env python3
# test_deepseek_api.py - Script to test DeepSeek API connection and response format

import os
import json
import requests
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get API key from environment
api_key = os.getenv("DEEPSEEK_API_KEY")
if not api_key:
    print("ERROR: No API key found. Please set DEEPSEEK_API_KEY in your .env file.")
    exit(1)

print(f"API key found (length: {len(api_key)})")

# Set up the request
url = "https://api.deepseek.com/v1/chat/completions"
headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}

# Test message
test_message = "Hi there, how are you today?"

payload = {
    "model": "deepseek-chat",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": test_message}
    ],
    "temperature": 0.7,
    "max_tokens": 300
}

# Make the API request
try:
    print(f"\nSending request to {url}...")
    print(f"Test message: '{test_message}'")
    
    response = requests.post(url, headers=headers, json=payload, timeout=20)
    
    print(f"\nResponse status code: {response.status_code}")
    print(f"Response headers: {json.dumps(dict(response.headers), indent=2)}")
    
    if response.status_code == 200:
        data = response.json()
        print("\nAPI Response Structure:")
        print(f"Top-level keys: {list(data.keys())}")
        
        # Pretty print the first 1000 characters of the response
        pretty_json = json.dumps(data, indent=2)
        print(f"\nResponse preview (first 1000 chars):\n{pretty_json[:1000]}...")
        
        # Try to extract the response using different paths
        print("\nAttempting to extract response content:")
        
        content_found = False
        
        # Standard path: choices[0].message.content
        if "choices" in data and len(data["choices"]) > 0:
            choice = data["choices"][0]
            if "message" in choice and "content" in choice["message"]:
                content = choice["message"]["content"]
                print(f"\n✅ Found content at standard path: choices[0].message.content")
                print(f"Content preview: '{content[:100]}...'")
                content_found = True
        
        # Check for other possible paths
        alternative_paths = [
            ("output", lambda d: d.get("output")),
            ("response", lambda d: d.get("response")),
            ("text", lambda d: d.get("text")),
            ("choices[0].text", lambda d: d.get("choices", [{}])[0].get("text")),
            ("completion", lambda d: d.get("completion"))
        ]
        
        for path_name, extractor in alternative_paths:
            value = extractor(data)
            if value and isinstance(value, str):
                print(f"\n✅ Found content at path: {path_name}")
                print(f"Content preview: '{value[:100]}...'")
                content_found = True
        
        if not content_found:
            print("\n❌ Could not find response content in any expected location")
            print("You may need to examine the response structure and update the extraction logic")
    else:
        print(f"\n❌ Error response from API: {response.text}")

except Exception as e:
    print(f"\n❌ Exception occurred: {str(e)}")

print("\nTest completed.")