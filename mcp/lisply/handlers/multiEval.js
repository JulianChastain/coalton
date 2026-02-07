/**
 * multiEval.js
 *
 * Handler for multi_eval tool - evaluates multiple forms.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleMultiEval: createBackendPostHandler('multi-eval', ['code'], 'MULTI-EVAL')
};
