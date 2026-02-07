/**
 * toolsList.js 
 * 
 * Handler for tools/list requests
 */

const { getBackendConnectionInfo, makeHttpRequest } = require('../lib/server');
const { sendStandardResponse, sendErrorResponse } = require('./index');
const { createPrefixedToolName } = require('../lib/config');

/**
 * Handle tools/list request
 */
function handleToolsList(request, config, logger) {
  logger.info('Handling tools/list request');
  
  const { hostname, port } = getBackendConnectionInfo(config, logger);
  
  const options = {
    hostname,
    port,
    path: `${config.BASE_PATH}/tools/list`,
    method: 'GET'
  };
  
  makeHttpRequest(options, null, (error, response) => {
    if (error) {
      logger.error(`Error fetching tools list: ${error.message}`);
      sendErrorResponse(request, -32603, `Error fetching tools list: ${error.message}`, logger);
      return;
    }
    
    try {
      const toolsData = JSON.parse(response.content);
      
      if (!toolsData.tools || !Array.isArray(toolsData.tools)) {
        throw new Error('Invalid tools list response format');
      }
      
      // Add mode parameter to lisp_eval if present
      for (const tool of toolsData.tools) {
        if (tool.name === 'lisp_eval' && tool.inputSchema?.properties) {
          if (!tool.inputSchema.properties.mode) {
            tool.inputSchema.properties.mode = {
              type: 'string',
              description: 'The mode to use to talk to Gendl, either http (default) or stdio.\nStdio will only be respected for local Gendl containers started by the MCP server itself.'
            };
          }
        }
      }
      
      // Add http_request tool if missing
      if (!toolsData.tools.some(t => t.name === 'http_request')) {
        toolsData.tools.push({
          name: 'http_request',
          description: 'Send an HTTP request to the specified path',
          inputSchema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'The path to send the request to' },
              method: { type: 'string', description: 'The HTTP method to use (GET, POST, PUT, DELETE, etc.)' },
              body: { type: 'string', description: 'The request body content (for POST/PUT requests)' },
              content: { type: 'string', description: 'Alternative name for the request body content (for compatibility)' },
              headers: { type: 'object', description: 'Optional headers to include with the request' },
              rawResponse: { type: 'boolean', description: 'If true, return the full response object instead of just the content' }
            },
            required: ['path']
          }
        });
      }
      
      // Add documentation tools if missing
      if (!toolsData.tools.some(t => t.name === 'get_docs_list')) {
        toolsData.tools.push({
          name: 'get_docs_list',
          description: 'List available documentation from the backend server',
          inputSchema: { type: 'object', properties: {}, required: [] }
        });
      }
      
      if (!toolsData.tools.some(t => t.name === 'get_docs')) {
        toolsData.tools.push({
          name: 'get_docs',
          description: 'Get documentation content from the backend server',
          inputSchema: {
            type: 'object',
            properties: {
              id: { type: 'string', description: "Document ID to retrieve (e.g., 'claude-md', 'readme', 'yadd')" }
            },
            required: ['id']
          }
        });
      }

      // Add new Coalton tools
      if (!toolsData.tools.some(t => t.name === 'type_of')) {
        toolsData.tools.push({
          name: 'type_of',
          description: 'Look up the type signature of a Coalton symbol',
          inputSchema: {
            type: 'object',
            properties: {
              name: { type: 'string', description: 'The symbol name to look up (e.g., "map", "fold")' }
            },
            required: ['name']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'list_definitions')) {
        toolsData.tools.push({
          name: 'list_definitions',
          description: 'List all value definitions in the current Coalton environment',
          inputSchema: {
            type: 'object',
            properties: {
              package: { type: 'string', description: 'Optional package name to filter by (e.g., "COALTON-USER")' }
            },
            required: []
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'apropos_coalton')) {
        toolsData.tools.push({
          name: 'apropos_coalton',
          description: 'Search for Coalton symbols matching a substring (case-insensitive)',
          inputSchema: {
            type: 'object',
            properties: {
              search: { type: 'string', description: 'The search string to match against symbol names' }
            },
            required: ['search']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'reset_environment')) {
        toolsData.tools.push({
          name: 'reset_environment',
          description: 'Reset the Coalton environment to its initial state (clears session definitions)',
          inputSchema: {
            type: 'object',
            properties: {},
            required: []
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'type_check_only')) {
        toolsData.tools.push({
          name: 'type_check_only',
          description: 'Type-check a Coalton expression without evaluating it. Returns the inferred type.',
          inputSchema: {
            type: 'object',
            properties: {
              code: { type: 'string', description: 'The Coalton expression to type-check' }
            },
            required: ['code']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'multi_eval')) {
        toolsData.tools.push({
          name: 'multi_eval',
          description: 'Evaluate multiple Coalton/CL forms in sequence, returning results for each',
          inputSchema: {
            type: 'object',
            properties: {
              code: { type: 'string', description: 'String containing multiple forms to evaluate' },
              package: { type: 'string', description: 'Optional package name for evaluation context' }
            },
            required: ['code']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'describe_symbol')) {
        toolsData.tools.push({
          name: 'describe_symbol',
          description: 'Get comprehensive information about a Coalton symbol: type, type-def, class-def, and CL description',
          inputSchema: {
            type: 'object',
            properties: {
              name: { type: 'string', description: 'The symbol name to describe' }
            },
            required: ['name']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'macroexpand_coalton')) {
        toolsData.tools.push({
          name: 'macroexpand_coalton',
          description: 'Show the Common Lisp code generated by the Coalton compiler for an expression',
          inputSchema: {
            type: 'object',
            properties: {
              code: { type: 'string', description: 'The Coalton expression to compile and show generated code for' }
            },
            required: ['code']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'disassemble_coalton')) {
        toolsData.tools.push({
          name: 'disassemble_coalton',
          description: 'Show the stored compiled code or disassembly for a Coalton function',
          inputSchema: {
            type: 'object',
            properties: {
              name: { type: 'string', description: 'The function name to disassemble' }
            },
            required: ['name']
          }
        });
      }

      if (!toolsData.tools.some(t => t.name === 'load_file')) {
        toolsData.tools.push({
          name: 'load_file',
          description: 'Load and evaluate a file containing Coalton/CL source code',
          inputSchema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Absolute path to the source file to load' },
              package: { type: 'string', description: 'Optional package name for evaluation context' }
            },
            required: ['path']
          }
        });
      }
      
      // Prefix all tool names with server name
      for (const tool of toolsData.tools) {
        const prefixed = createPrefixedToolName(config.SERVER_NAME, tool.name);
        if (prefixed !== tool.name) {
          logger.debug(`Prefixing tool: ${tool.name} -> ${prefixed}`);
          tool.name = prefixed;
        }
      }
      
      sendStandardResponse(request, toolsData, logger);
    } catch (parseError) {
      logger.error(`Error parsing tools list: ${parseError.message}`);
      sendErrorResponse(request, -32603, `Error parsing tools list: ${parseError.message}`, logger);
    }
  }, 'TOOLS-LIST', logger);
}

module.exports = { handleToolsList };
