/**
 * disassembleCoalton.js
 *
 * Handler for disassemble_coalton tool - shows stored code for a definition.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleDisassembleCoalton: createBackendPostHandler('disassemble-coalton', ['name'], 'DISASSEMBLE-COALTON')
};
