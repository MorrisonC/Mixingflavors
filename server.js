const express = require('express');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = 8080;

app.use(cors());

app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  next();
});

app.use(express.static(path.join(__dirname, 'build/web')));

app.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
