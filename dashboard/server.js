const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const CONFIG_FILE = path.join(__dirname, 'config.json');
const PUBLIC_DIR = path.join(__dirname, 'public');

// Ensure public directory exists
if (!fs.existsSync(PUBLIC_DIR)) {
  fs.mkdirSync(PUBLIC_DIR, { recursive: true });
}

// Helper to send JSON responses
function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  });
  res.end(JSON.stringify(data));
}

// Server request handler
const server = http.createServer((req, res) => {
  // Handle CORS Preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    });
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // ─── API Routes ──────────────────────────────────────────
  
  // GET /api/config
  if (pathname === '/api/config' && req.method === 'GET') {
    fs.readFile(CONFIG_FILE, 'utf8', (err, data) => {
      if (err) {
        return sendJSON(res, 500, { error: 'Failed to read configuration' });
      }
      try {
        const config = JSON.parse(data);
        sendJSON(res, 200, config);
      } catch (parseErr) {
        sendJSON(res, 500, { error: 'Invalid configuration format' });
      }
    });
    return;
  }

  // POST /api/config
  if (pathname === '/api/config' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
    });
    req.on('end', () => {
      try {
        const newConfig = JSON.parse(body);
        
        // Simple validations
        if (!newConfig.minVersion || !newConfig.latestVersion || !newConfig.updateUrl || !newConfig.notification) {
          return sendJSON(res, 400, { error: 'Missing required configuration fields' });
        }

        fs.writeFile(CONFIG_FILE, JSON.stringify(newConfig, null, 2), 'utf8', (err) => {
          if (err) {
            return sendJSON(res, 500, { error: 'Failed to save configuration' });
          }
          sendJSON(res, 200, { success: true, message: 'Configuration saved successfully', config: newConfig });
        });
      } catch (parseErr) {
        sendJSON(res, 400, { error: 'Invalid JSON request payload' });
      }
    });
    return;
  }

  // ─── Static File Server ───────────────────────────────────
  if (req.method === 'GET') {
    let filePath = path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname);
    
    // Security check: ensure path is inside PUBLIC_DIR
    if (!filePath.startsWith(PUBLIC_DIR)) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('Access Forbidden');
      return;
    }

    fs.stat(filePath, (err, stats) => {
      if (err || !stats.isFile()) {
        // Fallback to index.html for SPA router or 404
        filePath = path.join(PUBLIC_DIR, 'index.html');
      }

      fs.readFile(filePath, (readErr, content) => {
        if (readErr) {
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          res.end('File Not Found');
          return;
        }

        // Determine Content Type
        const ext = path.extname(filePath).toLowerCase();
        let contentType = 'text/html';
        if (ext === '.css') contentType = 'text/css';
        else if (ext === '.js') contentType = 'application/javascript';
        else if (ext === '.json') contentType = 'application/json';
        else if (ext === '.png') contentType = 'image/png';
        else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
        else if (ext === '.svg') contentType = 'image/svg+xml';
        else if (ext === '.ico') contentType = 'image/x-icon';

        res.writeHead(200, { 'Content-Type': contentType });
        res.end(content);
      });
    });
    return;
  }

  // Default Fallback
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

// Start Server
server.listen(PORT, () => {
  console.log(`=================================================`);
  console.log(`🚀 SliX TV Remote Config Dashboard running locally!`);
  console.log(`🌐 Web Console: http://localhost:${PORT}`);
  console.log(`📡 API Config Endpoint: http://localhost:${PORT}/api/config`);
  console.log(`=================================================`);
});
