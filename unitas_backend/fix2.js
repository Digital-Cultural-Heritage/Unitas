const fs = require('fs');
let c = fs.readFileSync('src/routes/events.js', 'utf8');
c = c.replace(/select\(\r?\n\s+id, title/g, 'select(`\n        id, title');
c = c.replace(/select\(\r?\n\s+id, created_at,/g, 'select(`\n        id, created_at,');
fs.writeFileSync('src/routes/events.js', c);
