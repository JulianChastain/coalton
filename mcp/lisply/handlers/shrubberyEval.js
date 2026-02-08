/**
 * shrubberyEval.js
 *
 * Handler for shrubbery_eval tool - parse and compile Coalton code
 * written in shrubbery/Rhombus notation.
 */

const { createBackendPostHandler } = require('./backendPost');

module.exports = {
  handleShrubberyEval: createBackendPostHandler('shrubbery-eval', ['code'], 'SHRUBBERY-EVAL')
};
