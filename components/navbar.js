class CustomNavbar extends HTMLElement {
  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    this.shadowRoot.innerHTML = `
      <style>
        nav {
          background: white;
          padding: 1rem 2rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
          position: sticky;
          top: 0;
          z-index: 50;
        }
        .logo {
          color: #2C3E50;
          font-weight: 700;
          font-size: 1.25rem;
          display: flex;
          align-items: center;
          gap: 0.5rem;
          text-decoration: none;
        }
        .logo:hover {
          opacity: 0.9;
        }
        .nav-links {
          display: flex;
          gap: 1.5rem;
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .nav-link {
          color: #4B5563;
          text-decoration: none;
          font-weight: 500;
          font-size: 0.95rem;
          transition: color 0.2s;
          display: flex;
          align-items: center;
          gap: 0.3rem;
        }
        .nav-link:hover {
          color: #2C3E50;
        }
        .nav-link.active {
          color: #764BA2;
        }
        .cta-button {
          background: linear-gradient(135deg, #2C3E50 0%, #764BA2 100%);
          color: white;
          padding: 0.5rem 1.25rem;
          border-radius: 0.375rem;
          font-weight: 500;
          transition: all 0.2s;
        }
        .cta-button:hover {
          opacity: 0.9;
          transform: translateY(-1px);
        }
        @media (max-width: 768px) {
          nav {
            flex-direction: column;
            gap: 1rem;
            padding: 1rem;
          }
          .nav-links {
            flex-direction: column;
            gap: 0.5rem;
            align-items: center;
            width: 100%;
          }
        }
      </style>
      <nav>
        <a href="/" class="logo">
          <i data-feather="dollar-sign"></i>
          Munger Money Mentor
        </a>
        <ul class="nav-links">
          <li><a href="/" class="nav-link"><i data-feather="home"></i> Home</a></li>
          <li><a href="/app.html" class="nav-link active"><i data-feather="zap"></i> App</a></li>
          <li><a href="#principles" class="nav-link"><i data-feather="shield"></i> Principles</a></li>
          <li><a href="https://github.com/your-repo" target="_blank" class="nav-link"><i data-feather="github"></i> GitHub</a></li>
          <li><a href="/app.html" class="cta-button">Try It Now</a></li>
        </ul>
      </nav>
    `;
  }
}
customElements.define('custom-navbar', CustomNavbar);