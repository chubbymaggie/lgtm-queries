// Copyright 2018 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * Provides classes for working with [Hapi](https://hapijs.com/) servers.
 */
import javascript
import semmle.javascript.frameworks.HTTP

module Hapi {
  /**
   * An expression that creates a new Hapi server.
   */
  class ServerDefinition extends HTTP::Servers::StandardServerDefinition, NewExpr {
    ServerDefinition() {
      exists (ModuleInstance hapi | hapi.getPath() = "hapi" |
        // `server = new Hapi.Server()`
        this.getCallee() = hapi.getAPropertyRead("Server")
      )
    }
  }

  /**
   * A Hapi route handler.
   */
  class RouteHandler extends HTTP::Servers::StandardRouteHandler {

    Function function;

    RouteHandler() {
      function = this and
      exists(RouteSetup setup | this = setup.getARouteHandler())
    }

    /**
     * Gets the parameter of the route handler that contains the request object.
     */
    SimpleParameter getRequestParameter() {
      result = function.getParameter(0)
    }
  }

  /**
   * A Hapi response source, that is, an access to the `response` property
   * of a request object.
   */
  private class ResponseSource extends HTTP::Servers::ResponseSource {
    RequestExpr req;

    ResponseSource() {
      asExpr().(PropAccess).accesses(req, "response")
    }

    /**
     * Gets the route handler that provides this response.
     */
    RouteHandler getRouteHandler() {
      result = req.getRouteHandler()
    }
  }

  /**
   * A Hapi request source, that is, the request parameter of a
   * route handler.
   */
  private class RequestSource extends HTTP::Servers::RequestSource {
    RouteHandler rh;

    RequestSource() {
      this = DataFlow::parameterNode(rh.getRequestParameter())
    }

    /**
     * Gets the route handler that handles this request.
     */
    RouteHandler getRouteHandler() {
      result = rh
    }
  }

  /**
   * A Hapi response expression.
   */
  class ResponseExpr extends HTTP::Servers::StandardResponseExpr {
    override ResponseSource src;
  }

  /**
   * An Hapi request expression.
   */
  class RequestExpr extends HTTP::Servers::StandardRequestExpr {
    override RequestSource src;
  }

  /**
   * An access to a user-controlled Hapi request input.
   */
  private class RequestInputAccess extends HTTP::RequestInputAccess {
    RouteHandler rh;
    string kind;

    RequestInputAccess() {
      exists (Expr request | request = rh.getARequestExpr() |
        kind = "body" and
        (
          // `request.rawPayload`
          this.asExpr().(PropAccess).accesses(request, "rawPayload") or
          exists (PropAccess payload |
            // `request.payload.name`
            payload.accesses(request, "payload")  and
            this.asExpr().(PropAccess).accesses(payload, _)
          )
        )
        or
        kind = "parameter" and
        exists (PropAccess query |
          // `request.query.name`
          query.accesses(request, "query")  and
          this.asExpr().(PropAccess).accesses(query, _)
        )
        or
        exists (PropAccess url |
          // `request.url.path`
          kind = "url" and
          url.accesses(request, "url")  and
          this.asExpr().(PropAccess).accesses(url, "path")
        )
        or
        exists (PropAccess headers |
          // `request.headers.<name>`
          kind = "header" and
          headers.accesses(request, "headers")  and
          this.asExpr().(PropAccess).accesses(headers, _)
        )
        or
        exists (PropAccess state |
          // `request.state.<name>`
          kind = "cookie" and
          state.accesses(request, "state")  and
          this.asExpr().(PropAccess).accesses(state, _)
        )
      )
    }

    override RouteHandler getRouteHandler() {
      result = rh
    }

    override string getKind() {
      result = kind
    }
  }

  /**
   * An HTTP header defined in a Hapi server.
   */
  private class HeaderDefinition extends HTTP::Servers::StandardHeaderDefinition {
    ResponseExpr res;

    HeaderDefinition() {
      // request.response.header('Cache-Control', 'no-cache')
      calls(res, "header")
    }

    override RouteHandler getRouteHandler(){
      result = res.getRouteHandler()
    }

  }

  /**
   * A call to a Hapi method that sets up a route.
   */
  class RouteSetup extends MethodCallExpr, HTTP::Servers::StandardRouteSetup {
    ServerDefinition server;
    string methodName;

    RouteSetup() {
      server.flowsTo(getReceiver()) and
      methodName = getMethodName() and
      (methodName = "route" or methodName = "ext")
    }

    override DataFlowNode getARouteHandler() {
      // server.route({ handler: fun })
      methodName = "route" and
      result = any(DataFlowNode n | hasOptionArgument(0, "handler", n)).getALocalSource()
      or
      // server.ext('/', fun)
      methodName = "ext" and result = getArgument(1).(DataFlowNode).getALocalSource()
    }

    override DataFlowNode getServer() {
      result = server
    }
  }
}
