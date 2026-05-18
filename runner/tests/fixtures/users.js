/**
 * Test users for saucedemo.com.
 *
 * Extracted into a fixture so we can easily fan out into per-user shards
 * in Week 3 (e.g., one K8s Job per user, all running in parallel).
 *
 * All passwords are publicly documented at https://www.saucedemo.com/
 * — these are not real credentials.
 */

const USERS = {
  STANDARD: {
    username: 'standard_user',
    password: 'secret_sauce',
    description: 'normal user, all flows work',
  },
  LOCKED_OUT: {
    username: 'locked_out_user',
    password: 'secret_sauce',
    description: 'login should fail with locked-out error',
  },
  PROBLEM: {
    username: 'problem_user',
    password: 'secret_sauce',
    description: 'logs in but inventory has visual bugs',
  },
  PERFORMANCE_GLITCH: {
    username: 'performance_glitch_user',
    password: 'secret_sauce',
    description: 'logs in slowly — good for timeout testing',
  },
};

module.exports = { USERS };