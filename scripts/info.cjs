#!/usr/bin/env node
'use strict';

const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  bgGreen: '\x1b[42m',
  black: '\x1b[30m',
};

const START_COMMAND = 'npm run local';
const DEV_COMMAND = 'npm run dev:app';
const INSTALL_COMMAND = 'npm run start';

const paint = {
  cmd: (text) => `${c.green}${text}${c.reset}`,
  phase: (text) => `${c.yellow}${text}${c.reset}`,
  dim: (text) => `${c.dim}${text}${c.reset}`,
  path: (text) => `${c.cyan}${text}${c.reset}`,
  guide: (text) => `${c.bold}${text}${c.reset}`,
  highlight: (text) => `${c.bold}${c.bgGreen}${c.black}${text}${c.reset}`,
  highlightCmd: (text) => `${c.bold}${c.green}${text}${c.reset}`,
};

const commands = [
  ['Start here', START_COMMAND, 'Build debug app and launch on macOS'],
  ['Develop', DEV_COMMAND, 'Build packages, test, build app, launch'],
  ['Install', INSTALL_COMMAND, 'Build release app + DMG → drag to Applications'],
  ['Setup', 'npm run setup:xcodegen', 'Install XcodeGen (once)'],
  ['Setup', 'npm run setup:xcode', 'Xcode first-launch (if build fails)'],
  ['Development', 'npm run build', 'Build Swift packages'],
  ['Development', 'npm run test', 'Run package tests'],
  ['Development', 'npm run build:app', 'Debug .app build'],
  ['Development', 'npm run run:app', 'Launch Nucleus.app on macOS'],
  ['Development', 'npm run app', 'Build app + launch on macOS'],
  ['Debug', 'npm run xcode', 'Build app + open Xcode (⌘R to debug)'],
  ['Debug', 'npm run open:xcode', 'Open Nucleus.xcodeproj only'],
  ['Release', 'npm run build:app:release', 'Release .app build only'],
  ['Help', 'npm run info', 'Show this guide'],
  ['Help', 'npm run init', 'Alias for info'],
];

const guides = [
  ['Local run', `${START_COMMAND}   (build debug Nucleus.app + launch)`],
  ['Test', `${DEV_COMMAND}   (packages + unit tests + launch Nucleus.app)`],
  ['Development', `${DEV_COMMAND} → edit Sources/ · app/ → repeat`],
  ['Debug', 'npm run xcode → scheme Nucleus → ⌘R · breakpoints · Instruments'],
  ['Operate app', 'Add Google accounts → Inbox · Calendar · Clipboard · Notes'],
  ['Music', 'Music sidebar → Set Up Access → Media & Apple Music + Automation (Nucleus → Music)'],
  ['Install', `${INSTALL_COMMAND} → open Nucleus.dmg → drag Nucleus.app to Applications`],
];

console.log('');
console.log(paint.highlight(' Nucleus '));
console.log(paint.guide('Personal Workspace for macOS'));
console.log('');

console.log(paint.phase('Quick start'));
console.log(`  ${paint.highlightCmd(START_COMMAND)}`);
console.log('');

console.log(paint.phase('Guides'));
for (const [title, detail] of guides) {
  console.log(`  ${paint.guide(title.padEnd(14))} ${paint.dim(detail)}`);
}
console.log('');

console.log(paint.phase('Commands'));
for (const [group, cmd, detail] of commands) {
  console.log(`  ${paint.guide(group.padEnd(12))} ${paint.cmd(cmd.padEnd(24))} ${paint.dim(detail)}`);
}
console.log('');

console.log(paint.phase('Layout'));
console.log(`  ${paint.path('nucleus/')}`);
console.log('  ├── app/                 SwiftUI desktop app');
console.log('  ├── Sources/             Swift packages (kits)');
console.log('  ├── Tests/');
console.log('  ├── scripts/');
console.log('  └── Package.swift');
console.log('');
