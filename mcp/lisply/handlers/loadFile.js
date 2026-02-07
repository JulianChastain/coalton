/**
 * loadFile.js
 *
 * Handler for load_file tool - loads and evaluates a Coalton source file.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleLoadFile: createBackendPostHandler('load-file', ['path'], 'LOAD-FILE')
};
