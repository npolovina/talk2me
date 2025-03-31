// src/components/CrisisAlert.jsx
const CrisisAlert = ({ onClose }) => {
    return (
      <div className="crisis-alert">
        <div className="crisis-content">
          <h2>Need immediate help?</h2>
          <p>If you're in crisis, please reach out for support right away:</p>
          <ul>
            <li>National Suicide Prevention Lifeline: <strong>988</strong></li>
            <li>Crisis Text Line: Text <strong>HOME to 741741</strong></li>
            <li>Call <strong>911</strong> or go to your nearest emergency room</li>
          </ul>
          <p>You matter. Help is available 24/7.</p>
          <button onClick={onClose} className="close-button">Close</button>
        </div>
      </div>
    );
  };
  
  export default CrisisAlert;