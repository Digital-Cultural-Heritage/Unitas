const fs = require('fs');
let c = fs.readFileSync('src/routes/events.js', 'utf8');
c = c.replace(/select\(\n\s+id, title/g, 'select(`\n        id, title');
c = c.replace(/created_at\n\s+\)/g, 'created_at\n      `)');
c = c.replace(/select\(\n\s+id, created_at,/g, 'select(`\n        id, created_at,');
c = c.replace(/angkatan\)\)\n\s+\)/g, 'angkatan))\n      `)');
fs.writeFileSync('src/routes/events.js', c);
