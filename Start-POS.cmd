@echo off
cd /d "%~dp0"
echo Starting Tailor Express POS...
echo Open http://localhost:3000 in your browser.
node --env-file-if-exists=.env --experimental-strip-types server/index.mjs
pause
