// src/components/Message.jsx
const Message = ({ message }) => {
    // Format timestamp
    const formatTime = (timestamp) => {
      return new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    };
    
    return (
      <div className={`message ${message.sender === 'user' ? 'user-message' : 'bot-message'}`}>
        <div className="message-content">
          <p>{message.text}</p>
        </div>
        <div className="message-timestamp">{formatTime(message.timestamp)}</div>
      </div>
    );
  };
  
  export default Message;