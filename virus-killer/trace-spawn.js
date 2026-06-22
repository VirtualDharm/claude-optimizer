// trace-spawn.js — reveal which module spawns the worm workers.
//
// The worm spawns `node -e global['...` via child_process. This preload hooks
// every spawn/exec/fork and, when the command looks like the worm, prints the
// full stack trace — the stack names the exact file/dependency responsible.
//
// Usage (from the infected project dir):
//   NODE_OPTIONS="--require /Users/mac/Projects2/claude-optimizer/virus-killer/trace-spawn.js" npm run start:dev
//
// Watch stderr for  >>> WORM SPAWN CAUGHT <<<  then read the stack lines.
'use strict';
const cp = require('child_process');
const fs = require('fs');
const LOG = require('os').homedir() + '/worm-spawn-trace.log';

function looksLikeWorm(args) {
  const s = JSON.stringify(args || '');
  return s.includes("global['") || s.includes('-e') && s.includes('global') ||
         s.includes('.node_modules') || s.includes('socket.io-client');
}

function report(method, cmd, args) {
  const stack = new Error().stack.split('\n').slice(2).join('\n');
  const out =
    '\n>>> WORM SPAWN CAUGHT <<< (' + method + ') ' + new Date().toISOString() +
    '\ncmd: ' + cmd +
    '\nargs: ' + JSON.stringify(args).slice(0, 300) +
    '\nSTACK (culprit = first non-node_modules/internal frame below):\n' + stack + '\n';
  process.stderr.write(out);
  try { fs.appendFileSync(LOG, out); } catch (e) {}
}

for (const m of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
  const orig = cp[m];
  if (typeof orig !== 'function') continue;
  cp[m] = function (cmd) {
    const args = Array.prototype.slice.call(arguments);
    try {
      if (looksLikeWorm([cmd].concat(args))) report(m, cmd, args);
    } catch (e) {}
    return orig.apply(this, arguments);
  };
}
process.stderr.write('[trace-spawn] active — log: ' + LOG + '\n');
