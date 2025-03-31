# app/main.py (updated version)
import time
import os
from fastapi import FastAPI, HTTPException, status, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.models import MessageRequest, MessageResponse
from app.services.chat_service import ChatService
from app.services.detection_service import DetectionService
from app.utils.helpers import detect_language
from app.utils.logger import logger
from app.utils.rate_limiter import RateLimiter
from fastapi import Depends

rate_limiter = RateLimiter(requests_per_minute=60)

# Create logs directory if it doesn't exist
os.makedirs("logs", exist_ok=True)

app = FastAPI(title="Talk2Me API", description="Health assistant chatbot API for Gen Z users")

# Initialize services
chat_service = ChatService()
detection_service = DetectionService()

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Replace with your frontend URL in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Middleware for request logging
@app.middleware("http")
async def log_requests(request: Request, call_next):
    request_id = str(time.time())
    logger.info(f"Request {request_id} started: {request.method} {request.url.path}")
    try:
        response = await call_next(request)
        logger.info(f"Request {request_id} completed with status code {response.status_code}")
        return response
    except Exception as e:
        logger.error(f"Request {request_id} failed with error: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"}
        )

@app.get("/")
async def root():
    logger.info("Root endpoint accessed")
    return {"message": "Welcome to Talk2Me API - Gen Z Health Assistant"}

@app.get("/health")
async def health_check():
    logger.info("Health check endpoint accessed")
    return {"status": "healthy", "timestamp": time.time()}

@app.post("/api/chat", response_model=MessageResponse)
async def chat(
    request: MessageRequest, 
    _: bool = Depends(rate_limiter)  # Apply rate limiting
):
    logger.info(f"Chat request received, message length: {len(request.message)}")
    
    user_message = request.message
    
    # Detect crisis 
    crisis_detected = detection_service.detect_crisis(user_message)
    if crisis_detected:
        logger.warning(f"Crisis detected in message: {user_message[:50]}...")
    
    # Detect language
    language = detect_language(user_message)
    logger.info(f"Detected language: {language}")
    
    # Categorize message
    categories = detection_service.categorize_message(user_message)
    if crisis_detected:
        categories.append("crisis")
    
    logger.info(f"Detected categories: {categories}")
    
    # Get resources
    resources = detection_service.get_related_resources(categories)
    
    # Generate appropriate system message
    system_message = chat_service.generate_system_message(categories, crisis_detected)
    
    try:
        # Get response from DeepSeek API
        ai_response = chat_service.get_chat_response(user_message, system_message)
        
        logger.info("Successfully generated AI response")
        
        response = MessageResponse(
            message=ai_response,
            detected_topics=categories,
            crisis_detected=crisis_detected,
            resources=resources
        )
        
        return response
    except Exception as e:
        logger.error(f"Error generating AI response: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred: {str(e)}"
        )

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Uncaught exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={"detail": "An unexpected error occurred. Please try again later."}
    )