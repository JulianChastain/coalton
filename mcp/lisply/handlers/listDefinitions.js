/**
 * listDefinitions.js
 *
 * Handler for list_definitions tool - lists all value definitions.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleListDefinitions: createBackendPostHandler('list-definitions', [], 'LIST-DEFINITIONS')
};
