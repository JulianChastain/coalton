/**
 * shrubberyTranslate.js
 *
 * Handler for shrubbery_translate tool - show Coalton S-expressions
 * that a shrubbery snippet translates to, without compiling.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleShrubberyTranslate: createBackendPostHandler('shrubbery-translate', ['code'], 'SHRUBBERY-TRANSLATE')
};
