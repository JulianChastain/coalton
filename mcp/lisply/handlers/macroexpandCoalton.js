/**
 * macroexpandCoalton.js
 *
 * Handler for macroexpand_coalton tool - shows generated CL code.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleMacroexpandCoalton: createBackendPostHandler('macroexpand-coalton', ['code'], 'MACROEXPAND-COALTON')
};
