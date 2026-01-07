const http = require('http');

const host = process.env.HOST || '0.0.0.0';
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello from Chainguard Node.js image!\n');
});

server.listen(port, host, () => {
  console.log(`Server running at http://${host}:${port}/`);
});
