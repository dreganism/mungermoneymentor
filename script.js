
// Shared JavaScript functionality
document.addEventListener('DOMContentLoaded', () => {
    // Initialize OpenAI API key from environment if available (guard for Node globals)
    if (!window.__OPENAI_API_KEY && typeof process !== 'undefined' && process.env && process.env.OPENAI_API_KEY) {
        window.__OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    }
    
    // Observe sections for scroll animations
const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate-fade-in');
            }
        });
    }, {
        threshold: 0.1
    });

    document.querySelectorAll('section').forEach((section, index) => {
        section.classList.add(`delay-${(index % 3) * 100}`);
        observer.observe(section);
    });

    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            document.querySelector(this.getAttribute('href')).scrollIntoView({
                behavior: 'smooth'
            });
        });
    });
});
