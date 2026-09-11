// Module resolution hooks that put the fakes beside this file where the relay
// expects the AWS SDK.
//
// `Relay/link/index.mjs` is deployed as one file: the Lambda runtime provides
// `@aws-sdk/client-dynamodb` and `@aws-sdk/client-apigatewaymanagementapi`, so
// the relay imports them by their bare names and this package has no
// dependencies and no `node_modules`. Under `node --test` those bare names
// resolve to nothing, and the alternative -- a `node_modules` tree checked into
// the repository -- puts two fakes somewhere nobody would look for them.
//
// A resolve hook maps the two specifiers to the files in this directory. The
// test imports those same specifiers, so it and the relay share one module
// instance, and so one in-memory table and one record of what was sent.
const fakes = {
  "@aws-sdk/client-dynamodb": "./client-dynamodb.mjs",
  "@aws-sdk/client-apigatewaymanagementapi": "./client-apigatewaymanagementapi.mjs",
};

export function resolve(specifier, context, nextResolve) {
  const fake = fakes[specifier];
  if (fake) {
    return { url: new URL(fake, import.meta.url).href, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}
