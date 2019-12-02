local typedefs = require "kong.db.schema.typedefs"

return {
  name = "r8limiter",
  fields = {
    {
      consumer = typedefs.no_consumer
    }, 
    {
      run_on = typedefs.run_on_first
    },
    {
      protocols = typedefs.protocols_http
    }, 
    {
      config = {
        type = "record",
        fields = {
          {
            descriptors = {
              type = "array",
              elements = {
                type = "record",
                fields = {
                  {
                    jwt_claims = {
                      type = "array",
                      elements = {
                        type = "record",
                        fields = {
                          {
                            claim = {
                              type = "string",
                              required = true
                            }
                          },
                          {
                            key = {
                              type = "string",
                              required = false
                            }
                          }
                        }
                      }
                    }
                  }, 
                  {
                    headers = {
                      type = "array",
                      elements = {
                        type = "record",
                        fields = {
                          {
                            header = {
                              type = "string",
                              required = true
                            }
                          },
                          {
                            key = {
                              type = "string",
                              required = false
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    ip_address = {
                      type = "boolean",
                      default = false
                    }
                  }
                }
              }
            }
          },
          {
            domain = {
              type = "string",
              required = false,
              default = "kong"
            }
          },
          {
            server = {
              type = "record",
              fields = {
                {
                  host = typedefs.host {
                    default = "localhost",
                  }
                },
                {
                  port = {
                    type = "number",
                    default = 8082,
                    between = {
                      0,
                      65534
                    },
                  },
                },  
                {
                  timeout = {
                    type = "number",
                    default = 100
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
