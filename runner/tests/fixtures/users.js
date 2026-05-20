/**
 * Test users for saucedemo.com.
 *
 * Each user has a defined behavior contract. Tests are parameterized to expect
 * the right behavior based on which user the runner pod is configured for.
 * This is what makes per-user sharding interesting: each shard validates a
 * different operational scenario.
 *
 * All passwords are publicly documented at https://www.saucedemo.com/
 * — these are not real credentials.
 */

const USERS = {
  STANDARD: {
    username: 'standard_user',
    password: 'secret_sauce',
    description: 'Standard customer flow — all interactions should work normally',
    expectations: {
      canLogin: true,
      inventoryRenders: true,
      cartWorks: true,
      checkoutWorks: true,
      hasVisualGlitches: false,
      isSlow: false,
    },
  },
  LOCKED_OUT: {
    username: 'locked_out_user',
    password: 'secret_sauce',
    description: 'Account is locked — login should fail with explicit error',
    expectations: {
      canLogin: false,
      lockoutErrorVisible: true,
    },
  },
  PROBLEM: {
    username: 'problem_user',
    password: 'secret_sauce',
    description: 'Can log in, but inventory has visual glitches and broken interactions',
    expectations: {
      canLogin: true,
      inventoryRenders: true,
      cartWorks: false,
      checkoutWorks: false,
      hasVisualGlitches: true,
      isSlow: false,
    },
  },
  PERFORMANCE_GLITCH: {
    username: 'performance_glitch_user',
    password: 'secret_sauce',
    description: 'Logs in successfully but with noticeable artificial delays',
    expectations: {
      canLogin: true,
      inventoryRenders: true,
      cartWorks: true,
      checkoutWorks: true,
      hasVisualGlitches: false,
      isSlow: true,
    },
  },
};

/**
 * Resolves which user this runner instance should test against.
 * Read from the SAUCE_USER environment variable, set in the K8s Job spec.
 * Defaults to STANDARD if unset (for local development convenience).
 */
function getUserForThisRun() {
  const userKey = process.env.SAUCE_USER || 'STANDARD';
  const user = USERS[userKey];
  if (!user) {
    const valid = Object.keys(USERS).join(', ');
    throw new Error(`Unknown SAUCE_USER: '${userKey}'. Valid values: ${valid}`);
  }
  return { key: userKey, ...user };
}

module.exports = { USERS, getUserForThisRun };