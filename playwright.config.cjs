const {defineConfig, devices} = require('@playwright/test');
const {existsSync} = require('node:fs');
const executablePath = process.env.CHROMIUM_PATH || (existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined);

module.exports = defineConfig({
  testDir: './test/browser',
  timeout: 75_000,
  expect: {timeout: 15_000},
  fullyParallel: false,
  workers: 1,
  reporter: [['list'], ['html', {open: 'never'}]],
  use: {
    baseURL: process.env.DEMO_URL || 'http://localhost:4000',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [{
    name: 'chromium',
    use: {...devices['Desktop Chrome'], viewport: {width: 1440, height: 1050},
      launchOptions: {executablePath}}
  }]
});
