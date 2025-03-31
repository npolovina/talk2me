// src/App.jsx
import { useState, useEffect } from 'react';
import './App.css';
import ChatInterface from './components/ChatInterface';
import Header from './components/Header';
import Footer from './components/Footer';
import LoadingScreen from './components/LoadingScreen';

function App() {
  const [isLoading, setIsLoading] = useState(true);
  
  useEffect(() => {
    // Simulate loading time
    const timer = setTimeout(() => {
      setIsLoading(false);
    }, 2000);
    
    return () => clearTimeout(timer);
  }, []);
  
  return (
    <div className="app-container">
      {isLoading ? (
        <LoadingScreen />
      ) : (
        <>
          <Header />
          <main>
            <ChatInterface />
          </main>
          <Footer />
        </>
      )}
    </div>
  );
}

export default App;