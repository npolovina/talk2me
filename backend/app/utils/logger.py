# app/utils/logger.py
import logging
import sys
import os
from datetime import datetime

def setup_logger():
    """Configure and return a logger for the application."""
    logger = logging.getLogger("talk2me")
    logger.setLevel(logging.INFO)
    
    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    
    # Create logs directory if it doesn't exist
    logs_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "logs")
    os.makedirs(logs_dir, exist_ok=True)
    
    # File handler for more permanent logging
    log_file_path = os.path.join(logs_dir, f"talk2me_{datetime.now().strftime('%Y%m%d')}.log")
    file_handler = logging.FileHandler(log_file_path)
    file_handler.setLevel(logging.INFO)
    
    # Format
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    console_handler.setFormatter(formatter)
    file_handler.setFormatter(formatter)
    
    # Add handlers
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    
    return logger

logger = setup_logger()