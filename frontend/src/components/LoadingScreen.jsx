// src/components/LoadingScreen.jsx
const LoadingScreen = () => {
    return (
      <div className="loading-screen">
        <div className="loading-content">
          <h1>Talk2Me</h1>
          <div className="loading-spinner">
            <div className="spinner"></div>
          </div>
          <p>Loading your health companion...</p>
        </div>
      </div>
    );
  };
  
  export default LoadingScreen;