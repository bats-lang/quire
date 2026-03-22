/**
 * Load WASM helper for Node.js testing.
 *
 * Reads bridge.js, strips the auto-boot lines at the bottom,
 * and re-exports loadWASM for controlled test use.
 */

import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const bridgeSrc = readFileSync(
  join(import.meta.dirname, '..', 'dist', 'pwa', 'bridge.js'),
  'utf-8'
);

// Strip auto-boot code (everything after the loadWASM function closing brace)
const bootMarker = "\nconst root = document.getElementById('bats-root');";
const idx = bridgeSrc.lastIndexOf(bootMarker);
if (idx < 0) throw new Error('Cannot find boot marker in bridge.js');

const tmpPath = join(tmpdir(), `bats-bridge-test-${process.pid}.mjs`);
writeFileSync(tmpPath, bridgeSrc.slice(0, idx) + '\n');

const mod = await import(tmpPath);
unlinkSync(tmpPath);

export const loadWASM = mod.loadWASM;
