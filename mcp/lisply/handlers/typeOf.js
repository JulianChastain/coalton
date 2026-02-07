/**
 * typeOf.js
 *
 * Handler for type_of tool - looks up the type of a Coalton symbol.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleTypeOf: createBackendPostHandler('type-of', ['name'], 'TYPE-OF')
};
