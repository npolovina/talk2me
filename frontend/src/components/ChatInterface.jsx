// src/components/ChatInterface.jsx
import { useState, useRef, useEffect } from 'react';
import Message from './Message';
import MoodSelector from './MoodSelector';
import ResourceLinks from './ResourceLinks';
import CrisisAlert from './CrisisAlert';

const ChatInterface = () => {
  const [messages, setMessages] = useState([
    { id: 1, text: "Hey! I'm Talk2Me, your health buddy. What's on your mind today?", sender: "bot", timestamp: new Date() }
  ]);
  const [input, setInput] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [showCrisisAlert, setShowCrisisAlert] = useState(false);
  const [resources, setResources] = useState([]);
  const messagesEndRef = useRef(null);
  const API_URL = process.env.REACT_APP_API_URL || '';
  
  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };
  
  useEffect(() => {
    scrollToBottom();
  }, [messages]);
  
  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!input.trim()) return;
    
    // Add user message
    const userMessage = {
      id: messages.length + 1,
      text: input,
      sender: "user",
      timestamp: new Date()
    };
    
    setMessages(prev => [...prev, userMessage]);
    setInput("");
    setIsTyping(true);
    
    try {
      // API call to backend
      const response = await fetch(`${API_URL}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: input }),
      });
      
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      
      const data = await response.json();
      
      // Check for crisis detection from backend
      if (data.crisis_detected) {
        setShowCrisisAlert(true);
      }
      
      // Update resources if provided
      if (data.resources && data.resources.length > 0) {
        // Process resources into categories
        const resourcesByCategory = {};
        
        data.resources.forEach(resource => {
          // Extract category from resource or use a default
          const category = resource.category || "General Resources";
          
          if (!resourcesByCategory[category]) {
            resourcesByCategory[category] = [];
          }
          
          resourcesByCategory[category].push({
            name: resource.name,
            url: resource.url,
            phone: resource.phone
          });
        });
        
        // Convert to format expected by ResourceLinks
        const formattedResources = Object.keys(resourcesByCategory).map(category => ({
          category,
          links: resourcesByCategory[category]
        }));
        
        setResources(formattedResources);
      }
      
      // Add bot response with typing effect delay
      setTimeout(() => {
        const botMessage = {
          id: messages.length + 2,
          text: data.message,
          sender: "bot",
          timestamp: new Date()
        };
        setMessages(prev => [...prev, botMessage]);
        setIsTyping(false);
      }, 1000);
      
    } catch (error) {
      console.error('Error:', error);
      // Error handling
      setTimeout(() => {
        const errorMessage = {
          id: messages.length + 2,
          text: "Sorry, I'm having trouble connecting right now. Please try again later.",
          sender: "bot",
          timestamp: new Date()
        };
        setMessages(prev => [...prev, errorMessage]);
        setIsTyping(false);
      }, 1000);
    }
  };
  
  return (
    <div className="chat-container">
      {showCrisisAlert && <CrisisAlert onClose={() => setShowCrisisAlert(false)} />}
      
      <div className="message-container">
        {messages.map((message) => (
          <Message key={message.id} message={message} />
        ))}
        
        {isTyping && (
          <div className="typing-indicator">
            <span></span>
            <span></span>
            <span></span>
          </div>
        )}
        
        <div ref={messagesEndRef} />
      </div>
      
      <MoodSelector />
      
      <form onSubmit={handleSubmit} className="input-form">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type your message here..."
          className="message-input"
        />
        <button type="submit" className="send-button">
          Send
        </button>
      </form>
      
      <ResourceLinks resources={resources} />
    </div>
  );
};

export default ChatInterface;