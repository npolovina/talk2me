from typing import List, Dict, Optional
from pydantic import BaseModel

class MessageRequest(BaseModel):
    message: str
    user_id: Optional[str] = None
    session_id: Optional[str] = None

class MessageResponse(BaseModel):
    message: str
    detected_topics: List[str] = []
    crisis_detected: bool = False
    resources: List[Dict] = []