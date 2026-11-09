const fs = require('fs');
let c = fs.readFileSync('src/routes/events.js', 'utf8');
c = c.replace(/id,\s+created_at,/g, 'id, registered_at,');
c = c.replace(/\.order\("created_at"/g, '.order("registered_at"');
fs.writeFileSync('src/routes/events.js', c);
