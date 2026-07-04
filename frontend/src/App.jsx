import React, { useEffect, useState } from 'react';

export default function App() {
  const [rootMsg, setRootMsg] = useState('Loading...');
  const [health, setHealth] = useState(null);
  const [loadingHealth, setLoadingHealth] = useState(false);

  useEffect(() => {
    // call backend root via /api/ (nginx proxy)
    fetch('/api/')
      .then((r) => r.text())
      .then(setRootMsg)
      .catch(() => setRootMsg('Unable to reach backend'));
  }, []);

  const checkHealth = async () => {
    setLoadingHealth(true);
    try {
      const res = await fetch('/api/health');
      const json = await res.json();
      setHealth(json);
    } catch (e) {
      setHealth({ error: 'Request failed' });
    } finally {
      setLoadingHealth(false);
    }
  };

  return (
    <div className="container">
      <header>
        <h1>DevOps Assessment Frontend</h1>
        <p className="subtitle">Simple React + Vite app served by nginx</p>
      </header>

      <main>
        <section className="card">
          <h2>Backend root response</h2>
          <p className="mono">{rootMsg}</p>
        </section>

        <section className="card">
          <h2>Health check</h2>
          <button onClick={checkHealth} disabled={loadingHealth}>
            {loadingHealth ? 'Checking...' : 'Check backend /health'}
          </button>
          {health && (
            <pre className="mono">{JSON.stringify(health, null, 2)}</pre>
          )}
        </section>
      </main>

      <footer>
        <small>Responsive UI • Environment variables via build</small>
      </footer>
    </div>
  );
}
