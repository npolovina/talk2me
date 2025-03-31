from langdetect import detect, LangDetectException

def detect_language(text):
    """Detect the language of a text."""
    try:
        return detect(text)
    except LangDetectException:
        return "en"  # Default to English

def safe_get(data, keys, default=None):
    """Safely get nested dictionary values."""
    if not data:
        return default
    
    if isinstance(keys, str):
        keys = [keys]
    
    for key in keys:
        if isinstance(data, dict) and key in data:
            data = data[key]
        else:
            return default
    return data