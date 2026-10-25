const assert = require("node:assert/strict");
const test = require("node:test");

const { bearerToken } = require("../lib/authorization.js");

test("extracts only a bearer authentication token", () => {
  assert.equal(bearerToken("Bearer valid-token"), "valid-token");
  assert.equal(bearerToken("Basic credentials"), null);
  assert.equal(bearerToken(undefined), null);
});
