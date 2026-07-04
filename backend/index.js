const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Simple middleware to log requests
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  next();
});

app.get('/', (req, res) => {
  res.type('text').send('Application is running');
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Example: optional DB env vars (not used here)
const dbHost = process.env.DB_HOST || null;
if (dbHost) {
  console.log('DB_HOST is set (not connected in this sample):', dbHost);
}

app.listen(port, () => {
  console.log(`Backend listening on port ${port}`);
});
