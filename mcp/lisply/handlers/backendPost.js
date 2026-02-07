/**
 * backendPost.js
 *
 * Shared factory for creating POST-to-backend handlers.
 */

const { getBackendConnectionInfo, makeHttpRequest } = require('../lib/server');
const { sendTextResponse, sendErrorResponse } = require('./index');

/**
 * Create a handler function that POSTs to a backend endpoint.
 *
 * @param {string} endpointSuffix - Path suffix after /lisply/ (e.g. 'type-of')
 * @param {string[]} requiredParams - Parameter names that must be present in args
 * @param {string} logPrefix - Prefix for log messages
 * @returns {function} Handler function (request, args, config, logger)
 */
function createBackendPostHandler(endpointSuffix, requiredParams, logPrefix) {
  return function handler(request, args, config, logger) {
    logger.info(`[${logPrefix}] Handling request`);

    // Validate required params
    for (const param of requiredParams) {
      if (!args[param]) {
        sendErrorResponse(request, -32602, `Missing required parameter: ${param}`, logger);
        return;
      }
    }

    const payload = JSON.stringify(args);
    const { hostname, port } = getBackendConnectionInfo(config, logger);

    const options = {
      hostname,
      port,
      path: `${config.BASE_PATH}/${endpointSuffix}`,
      method: 'POST',
      timeoutMs: config.REQUEST_TIMEOUT_MS,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    };

    makeHttpRequest(options, payload, (error, response) => {
      if (error) {
        logger.error(`[${logPrefix}] Error: ${error.message}`);
        sendErrorResponse(request, -32603, `Error: ${error.message}`, logger);
        return;
      }

      try {
        const result = JSON.parse(response.content);

        if ('success' in result) {
          if (result.success) {
            logger.info(`[${logPrefix}] Success`);
            const text = typeof result.result === 'string'
              ? result.result
              : JSON.stringify(result.result, null, 2);
            sendTextResponse(request, text, logger);
          } else {
            logger.error(`[${logPrefix}] Failed: ${result.error}`);
            sendErrorResponse(request, -32603, result.error || 'Unknown error', logger);
          }
        } else {
          sendTextResponse(request, JSON.stringify(result, null, 2), logger);
        }
      } catch (e) {
        logger.debug(`[${logPrefix}] Non-JSON response: ${e.message}`);
        sendTextResponse(request, response.content, logger);
      }
    }, logPrefix, logger);
  };
}

module.exports = { createBackendPostHandler };
