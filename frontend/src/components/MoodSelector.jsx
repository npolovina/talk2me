// src/components/MoodSelector.jsx
import { useState } from 'react';

const MoodSelector = () => {
  const [selectedMood, setSelectedMood] = useState(null);
  const moods = [
    { emoji: "😊", label: "Happy" },
    { emoji: "😐", label: "Neutral" },
    { emoji: "😔", label: "Sad" },
    { emoji: "😡", label: "Angry" },
    { emoji: "😰", label: "Anxious" }
  ];
  
  const handleMoodSelect = (index) => {
    setSelectedMood(index);
    // Here you could also send this data to your backend
    console.log(`Mood selected: ${moods[index].label}`);
  };
  
  return (
    <div className="mood-selector">
      <p>How are you feeling today?</p>
      <div className="mood-options">
        {moods.map((mood, index) => (
          <button 
            key={index} 
            className={`mood-button ${selectedMood === index ? 'selected' : ''}`}
            onClick={() => handleMoodSelect(index)}
            aria-label={mood.label}
          >
            {mood.emoji}
          </button>
        ))}
      </div>
    </div>
  );
};

export default MoodSelector;