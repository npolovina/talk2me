# app/services/chat_service.py
import os
import requests
from app.utils.helpers import safe_get
from app.utils.logger import logger

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
        """Get response from DeepSeek API."""
        if not system_message:
            system_message = "You are Talk2Me, a friendly and supportive healthcare assistant for Gen Z users. Use casual, conversational language appropriate for teens and young adults. Keep responses concise, authentic, and supportive."
        
        # If in mock mode, return a mock response
        if self.mock_mode:
            logger.info("Using mock response in mock mode")
            return "Hey there! This is a mock response from Talk2Me. In a real deployment, I'd connect to the DeepSeek API to give you a personalized response. How can I help you today?"
        
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
            "temperature": 0.7
        }
        
        try:
            logger.info("Sending request to DeepSeek API")
            response = requests.post(
                self.api_url, 
                headers=headers,
                json=payload,
                timeout=10
            )
            
            response.raise_for_status()
            data = response.json()
            
            ai_response = safe_get(data, ["choices", 0, "message", "content"], 
                          "I'm sorry, I couldn't generate a response at the moment.")
            
            logger.info("Received response from DeepSeek API")
            return ai_response
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Error calling DeepSeek API: {str(e)}")
            return "I'm having trouble connecting right now. Please try again later."