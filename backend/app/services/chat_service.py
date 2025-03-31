# app/services/chat_service.py
import os
import requests
import json
from app.utils.helpers import safe_get
from app.utils.logger import logger

# Try to import mock responses, but don't fail if not available
try:
    from app.utils.mock_responses import get_mock_response
except ImportError:
    def get_mock_response(msg): return "Mock response fallback"

class ChatService:
    """Service for handling chat interactions with DeepSeek API."""
    
    def __init__(self):
        self.api_key = os.getenv("DEEPSEEK_API_KEY")
        self.api_url = "https://api.deepseek.com/v1/chat/completions"
        self.mock_mode = os.getenv("MOCK_MODE", "false").lower() == "true"
        
        if not self.api_key and not self.mock_mode:
            logger.warning("DEEPSEEK_API_KEY not set and mock mode is disabled")
            raise ValueError("DEEPSEEK_API_KEY environment variable not set")
        
        if self.mock_mode:
            logger.info("Running in MOCK MODE - no API calls will be made")
        else:
            logger.info("Running in LIVE MODE - API calls will be made to DeepSeek")
    
    def generate_system_message(self, categories, crisis_detected):
        """Generate appropriate system message based on detected topics."""
        system_message = "You are Talk2Me, a friendly and supportive health assistant for Gen Z users. "
        
        if crisis_detected:
            system_message += "I notice this conversation involves serious topics that may indicate a crisis. Provide empathetic, supportive responses while emphasizing the importance of seeking professional help immediately. Mention crisis resources like the 988 Suicide & Crisis Lifeline."
        elif "mental_health" in categories:
            system_message += "Focus on providing mental health support in a non-judgmental way. Suggest healthy coping mechanisms and resources when appropriate."
        elif "sexual_health" in categories:
            system_message += "Provide accurate, judgment-free information about sexual health. Emphasize safety, consent, and responsible choices."
        elif "substance_use" in categories:
            system_message += "Discuss substance use with a harm-reduction approach. Provide factual information and avoid judgmental language."
        
        system_message += " Use casual, conversational language appropriate for teens and young adults. Keep responses concise (under 150 words), authentic, and supportive."
        
        return system_message
    
    def get_chat_response(self, user_message, system_message=None):
        """Get response from DeepSeek API or mock responses in test mode."""
        if not system_message:
            system_message = "You are Talk2Me, a friendly and supportive healthcare assistant for Gen Z users. Use casual, conversational language appropriate for teens and young adults. Keep responses concise, authentic, and supportive."
        
        # If in mock mode, return a mock response
        if self.mock_mode:
            logger.info("Using mock response in mock mode")
            mock_response = get_mock_response(user_message)
            logger.info(f"Generated mock response for: {user_message[:30]}...")
            return mock_response
        
        # Log the API key length (for debugging, don't log the actual key)
        api_key_status = "Not Set" if not self.api_key else f"Set (length: {len(self.api_key)})"
        logger.info(f"Using DeepSeek API. API Key status: {api_key_status}")
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": system_message},
                {"role": "user", "content": user_message}
            ],
            "temperature": 0.7,
            "max_tokens": 500  # Limit response length
        }
        
        try:
            logger.info(f"Sending request to DeepSeek API: {self.api_url}")
            response = requests.post(
                self.api_url, 
                headers=headers,
                json=payload,
                timeout=20  # Increased timeout for API calls
            )
            
            # Log response status and headers for debugging
            logger.info(f"DeepSeek API response status: {response.status_code}")
            logger.info(f"DeepSeek API response headers: {dict(response.headers)}")
            
            if response.status_code != 200:
                logger.error(f"DeepSeek API error: {response.text}")
                return "Sorry, there was an error connecting to the AI service. Please try again later."
            
            data = response.json()
            logger.info(f"DeepSeek API response data structure: {list(data.keys())}")
            
            # Log more detailed structure of the response for debugging
            logger.info(f"Full response structure: {json.dumps(data, indent=2)[:500]}...")
            
            # Try multiple paths to extract the content
            ai_response = None
            
            # Try the standard path first
            if "choices" in data and len(data["choices"]) > 0:
                choice = data["choices"][0]
                if "message" in choice and "content" in choice["message"]:
                    ai_response = choice["message"]["content"]
                    logger.info("Extracted response from standard path: choices[0].message.content")
            
            # If that fails, try alternative paths that might exist in the DeepSeek API
            if not ai_response and "output" in data:
                ai_response = data["output"]
                logger.info("Extracted response from alternative path: output")
            
            if not ai_response and "response" in data:
                ai_response = data["response"]
                logger.info("Extracted response from alternative path: response")
            
            if not ai_response and "text" in data:
                ai_response = data["text"]
                logger.info("Extracted response from alternative path: text")
            
            # Final fallback - try to convert the entire response to a string if all else fails
            if not ai_response:
                logger.warning("Could not find response in expected fields, using fallback extraction")
                # Try to extract text from any field that might contain the response
                for key, value in data.items():
                    if isinstance(value, str) and len(value) > 20:  # Look for substantial text
                        ai_response = value
                        logger.info(f"Extracted response from field: {key}")
                        break
            
            if not ai_response:
                logger.warning("Empty or missing response from DeepSeek API")
                return "Hey, I'm having trouble coming up with a good response right now. Could you try asking me something else or rephrasing your question?"
            
            logger.info("Received valid response from DeepSeek API")
            logger.info(f"Response length: {len(ai_response)} characters")
            return ai_response
            
        except requests.exceptions.Timeout:
            logger.error("Timeout error calling DeepSeek API")
            return "Sorry, it's taking longer than expected to process your request. The servers might be busy. Could you try again in a moment?"
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Error calling DeepSeek API: {str(e)}")
            return "I'm having a hard time connecting right now. My servers might be down or experiencing issues. Can we try again in a bit?"
        
        except Exception as e:
            logger.error(f"Unexpected error in API call: {str(e)}")
            return "Something unexpected happened. Please try again later."