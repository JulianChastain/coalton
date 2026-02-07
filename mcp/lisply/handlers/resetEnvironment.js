/**
 * resetEnvironment.js
 *
 * Handler for reset_environment tool - resets the Coalton environment.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleResetEnvironment: createBackendPostHandler('reset-environment', [], 'RESET-ENVIRONMENT')
};
