/**
 * aproposCoalton.js
 *
 * Handler for apropos_coalton tool - searches Coalton symbols.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleAproposCoalton: createBackendPostHandler('apropos-coalton', ['search'], 'APROPOS-COALTON')
};
