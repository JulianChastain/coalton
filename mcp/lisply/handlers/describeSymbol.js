/**
 * describeSymbol.js
 *
 * Handler for describe_symbol tool - comprehensive symbol description.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleDescribeSymbol: createBackendPostHandler('describe-symbol', ['name'], 'DESCRIBE-SYMBOL')
};
