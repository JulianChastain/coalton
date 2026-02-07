/**
 * typeCheck.js
 *
 * Handler for type_check_only tool - type-checks without evaluating.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleTypeCheck: createBackendPostHandler('type-check', ['code'], 'TYPE-CHECK')
};
