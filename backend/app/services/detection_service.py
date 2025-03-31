class DetectionService:
    """Service for content detection and categorization."""
    
    @staticmethod
    def detect_crisis(text):
        """Detect potential crisis indicators in user message."""
        crisis_keywords = [
            "suicide", "kill myself", "end my life", "don't want to live",
            "self harm", "hurt myself", "cutting myself", "overdose"
        ]
        text_lower = text.lower()
        return any(keyword in text_lower for keyword in crisis_keywords)
    
    @staticmethod
    def categorize_message(text):
        """Categorize the message into relevant health topics."""
        categories = {
            "mental_health": ["anxiety", "depression", "stress", "overwhelm", "therapy", "counseling"],
            "sexual_health": ["sex", "contraception", "protection", "std", "sti", "abortion", "pregnancy"],
            "substance_use": ["drugs", "alcohol", "addiction", "smoking", "vape", "marijuana", "weed"],
            "physical_health": ["exercise", "workout", "diet", "nutrition", "sleep", "eating"],
            "relationships": ["friend", "partner", "dating", "breakup", "relationship", "family"]
        }
        
        text_lower = text.lower()
        detected_categories = []
        
        for category, keywords in categories.items():
            if any(keyword in text_lower for keyword in keywords):
                detected_categories.append(category)
        
        return detected_categories
    
    @staticmethod
    def get_related_resources(categories):
        """Get related resources based on detected categories."""
        resource_map = {
            "mental_health": [
                {"name": "National Alliance on Mental Health", "url": "https://www.nami.org", "phone": "800-950-6264"},
                {"name": "Calm App", "url": "https://www.calm.com"}
            ],
            "sexual_health": [
                {"name": "Planned Parenthood", "url": "https://www.plannedparenthood.org", "phone": "800-230-7526"},
                {"name": "CDC Sexual Health", "url": "https://www.cdc.gov/sexualhealth/"}
            ],
            "substance_use": [
                {"name": "SAMHSA Helpline", "url": "https://www.samhsa.gov", "phone": "800-662-4357"},
                {"name": "Teen Drug Abuse", "url": "https://www.drugabuse.gov/drug-topics/trends-statistics/infographics/monitoring-future-2020-survey-results"}
            ],
            "physical_health": [
                {"name": "MyFitnessPal", "url": "https://www.myfitnesspal.com"},
                {"name": "CDC Physical Activity", "url": "https://www.cdc.gov/physicalactivity/"}
            ],
            "relationships": [
                {"name": "Love Is Respect", "url": "https://www.loveisrespect.org", "phone": "866-331-9474"},
                {"name": "7 Cups - Online Therapy", "url": "https://www.7cups.com"}
            ],
            "crisis": [
                {"name": "National Suicide Prevention Lifeline", "url": "https://suicidepreventionlifeline.org/", "phone": "988"},
                {"name": "Crisis Text Line", "url": "https://www.crisistextline.org/", "text": "HOME to 741741"}
            ]
        }
        
        resources = []
        for category in categories:
            if category in resource_map:
                resources.extend(resource_map[category])
        
        # Add crisis resources if no specific categories are detected
        if not resources:
            resources = resource_map.get("mental_health", [])[:1]
        
        return resources