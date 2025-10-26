class CustomFooter extends HTMLElement {
  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    this.shadowRoot.innerHTML = `
      <style>
        footer {
          background: #2C3E50;
          color: white;
          padding: 3rem 1rem;
          margin-top: auto;
        }
        .footer-container {
          max-width: 1200px;
          margin: 0 auto;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 2rem;
        }
        .footer-logo {
          font-weight: 700;
          font-size: 1.25rem;
          margin-bottom: 1rem;
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .footer-links {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .footer-link {
          color: #E5E7EB;
          text-decoration: none;
          transition: opacity 0.2s;
        }
        .footer-link:hover {
          opacity: 0.8;
        }
        .footer-bottom {
          text-align: center;
          margin-top: 3rem;
          padding-top: 1.5rem;
          border-top: 1px solid rgba(255,255,255,0.1);
          color: #9CA3AF;
          font-size: 0.875rem;
        }
        .social-links {
          display: flex;
          gap: 1rem;
          margin-top: 1rem;
        }
        .social-link {
          color: white;
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: rgba(255,255,255,0.1);
          display: flex;
          align-items: center;
          justify-content: center;
          transition: background 0.2s;
        }
        .social-link:hover {
          background: rgba(255,255,255,0.2);
        }
        @media (max-width: 768px) {
          .footer-container {
            grid-template-columns: 1fr;
            text-align: center;
          }
          .social-links {
            justify-content: center;
          }
        }
      </style>
      <footer>
        <div class="footer-container">
          <div>
            <div class="footer-logo">
              <i data-feather="dollar-sign"></i>
              Munger Money Mentor
            </div>
            <p class="text-gray-300 mt-2">Applying Charlie Munger's timeless financial wisdom to modern decisions.</p>
            <div class="social-links">
              <a href="#" class="social-link"><i data-feather="twitter"></i></a>
              <a href="#" class="social-link"><i data-feather="github"></i></a>
              <a href="#" class="social-link"><i data-feather="linkedin"></i></a>
            </div>
          </div>
          <div>
            <h4 class="font-bold text-lg mb-4">Resources</h4>
            <div class="footer-links">
              <a href="#" class="footer-link"><i data-feather="book" class="w-4 h-4 mr-2"></i> Principles</a>
              <a href="#" class="footer-link"><i data-feather="file-text" class="w-4 h-4 mr-2"></i> Documentation</a>
              <a href="#" class="footer-link"><i data-feather="github" class="w-4 h-4 mr-2"></i> GitHub</a>
            </div>
          </div>
          <div>
            <h4 class="font-bold text-lg mb-4">Legal</h4>
            <div class="footer-links">
              <a href="#" class="footer-link">Privacy Policy</a>
              <a href="#" class="footer-link">Terms of Service</a>
              <a href="#" class="footer-link">Disclaimer</a>
            </div>
          </div>
        </div>
        <div class="footer-bottom">
          <p>&copy; 2024 Munger Money Mentor. Not affiliated with Charlie Munger or Berkshire Hathaway.</p>
          <p class="mt-1">Educational tool, not financial advice.</p>
        </div>
      </footer>
    `;
  }
}
customElements.define('custom-footer', CustomFooter);