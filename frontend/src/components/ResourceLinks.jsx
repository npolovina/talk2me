// src/components/ResourceLinks.jsx
const ResourceLinks = ({ resources = [] }) => {
    // Default resources to show if none provided
    const defaultResources = [
      {
        category: "Mental Health",
        links: [
          { name: "National Alliance on Mental Health", url: "https://www.nami.org" },
          { name: "Calm App", url: "https://www.calm.com" }
        ]
      },
      {
        category: "Sexual Health",
        links: [
          { name: "Planned Parenthood", url: "https://www.plannedparenthood.org" },
          { name: "CDC Sexual Health", url: "https://www.cdc.gov/sexualhealth/" }
        ]
      }
    ];
    
    // Use provided resources or fall back to defaults
    const displayResources = resources.length > 0 ? resources : defaultResources;
    
    return (
      <div className="resource-links">
        <h3>Helpful Resources</h3>
        <div className="resources-container">
          {displayResources.map((resource, index) => (
            <div key={index} className="resource-category">
              <h4>{resource.category}</h4>
              <ul>
                {resource.links.map((link, linkIndex) => (
                  <li key={linkIndex}>
                    <a href={link.url} target="_blank" rel="noopener noreferrer">
                      {link.name}
                    </a>
                    {link.phone && <span> • {link.phone}</span>}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    );
  };
  
  export default ResourceLinks;