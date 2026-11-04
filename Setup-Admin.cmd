@echo off
cd /d "%~dp0"
node --env-file-if-exists=.env --experimental-strip-types server/setup-admin.mjs
pause
