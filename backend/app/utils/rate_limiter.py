# app/utils/rate_limiter.py
import time
from collections import defaultdict
from fastapi import HTTPException, Request, status

class RateLimiter:
    def __init__(self, requests_per_minute=60):
        self.requests_per_minute = requests_per_minute
        self.requests = defaultdict(list)
    
    async def __call__(self, request: Request):
        client_ip = request.client.host
        current_time = time.time()
        
        # Remove requests older than 1 minute
        self.requests[client_ip] = [req_time for req_time in self.requests[client_ip] 
                                   if current_time - req_time < 60]
        
        # Check if client has exceeded rate limit
        if len(self.requests[client_ip]) >= self.requests_per_minute:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Rate limit exceeded. Please try again later."
            )
        
        # Add current request timestamp
        self.requests[client_ip].append(current_time)
        
        return True