// src/components/ResourceLinks.jsx
const ResourceLinks = () => {
    const resources = [
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
    
    return (
      <div className="resource-links">
        <h3>Helpful Resources</h3>
        <div className="resources-container">
          {resources.map((resource, index) => (
            <div key={index} className="resource-category">
              <h4>{resource.category}</h4>
              <ul>
                {resource.links.map((link, linkIndex) => (
                  <li key={linkIndex}>
                    <a href={link.url} target="_blank" rel="noopener noreferrer">
                      {link.name}
                    </a>
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