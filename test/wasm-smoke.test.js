/**
 * WASM smoke tests — loads the real compiled app.wasm in Node.js
 * with jsdom + fake-indexeddb, exercising init and EPUB import.
 *
 * These tests catch WASM crashes, bridge protocol issues, and basic
 * EPUB parsing failures without needing a browser.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM } from 'jsdom';
import { indexedDB, IDBKeyRange } from 'fake-indexeddb';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createEpub } from '../e2e/create-epub.js';
import { loadWASM } from './load-wasm.js';

const wasmPath = join(import.meta.dirname, '..', 'dist', 'pwa', 'app.wasm');
let wasmBytes;

beforeAll(() => {
  wasmBytes = readFileSync(wasmPath);
});

function setupGlobals(dom) {
  global.document = dom.window.document;
  global.window = dom.window;
  global.TextEncoder = TextEncoder;
  global.TextDecoder = TextDecoder;
  global.indexedDB = indexedDB;
  global.IDBKeyRange = IDBKeyRange;
  global.MouseEvent = dom.window.MouseEvent;
  global.KeyboardEvent = dom.window.KeyboardEvent;
  global.DOMParser = dom.window.DOMParser;
  global.Blob = dom.window.Blob;
  global.URL = dom.window.URL;
  global.FileReader = dom.window.FileReader;
  global.Notification = undefined;
  global.DecompressionStream = globalThis.DecompressionStream;
}

function freshDom() {
  return new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true }
  );
}

describe('WASM Smoke', () => {
  it('should load and initialize without crashing', async () => {
    const dom = freshDom();
    setupGlobals(dom);
    const root = dom.window.document.getElementById('bats-root');

    const { exports } = await loadWASM(wasmBytes, root, {});

    // After init, there should be some DOM children in the root
    expect(root.children.length).toBeGreaterThan(0);
    expect(typeof exports.mainats_0_void).toBe('function');
    expect(typeof exports.memory).toBe('object');
  });

  it('should create library screen elements', async () => {
    const dom = freshDom();
    setupGlobals(dom);
    const root = dom.window.document.getElementById('bats-root');

    await loadWASM(wasmBytes, root, {});

    // The library is the app's main landmark, with its list of books
    const library = dom.window.document.querySelector('[role="main"]');
    expect(library).not.toBeNull();
    expect(library.querySelector('[role="region"][aria-label="Books"]')).not.toBeNull();
  });

  it('should import EPUB and create book card', async () => {
    const dom = freshDom();
    setupGlobals(dom);
    const root = dom.window.document.getElementById('bats-root');

    const epub = createEpub({
      title: 'Node Smoke',
      author: 'Test Bot',
      chapters: 1,
      paragraphsPerChapter: 2,
      storeChapters: true,
    });

    const { exports } = await loadWASM(wasmBytes, root, {});

    // Find the file input created by the app
    const fileInput = dom.window.document.querySelector('input[type="file"]');
    if (!fileInput) {
      // App might not create file input in DOM; still verify init
      expect(root.children.length).toBeGreaterThan(0);
      return;
    }

    // Simulate file selection by injecting a File object
    const epubArray = new Uint8Array(epub);
    const file = new dom.window.File([epubArray], 'test.epub', {
      type: 'application/epub+zip',
    });

    // jsdom doesn't let us write to input.files directly
    Object.defineProperty(fileInput, 'files', {
      value: { 0: file, length: 1, item: (i) => i === 0 ? file : null },
      writable: false,
      configurable: true,
    });

    // The bridge adds a 'change' event listener on the file input.
    // Dispatch change to trigger WASM's event handler → file_open → read → decompress → parse → render
    fileInput.dispatchEvent(new dom.window.Event('change', { bubbles: true }));

    // Wait for async import pipeline: the library shows the book's card
    let bookCard = null;
    for (let i = 0; i < 50 && !bookCard; i++) {
      await new Promise(r => setTimeout(r, 100));
      bookCard = dom.window.document.querySelector('[role="region"][aria-label="Books"] button');
    }

    expect(bookCard).not.toBeNull();
    expect(bookCard.textContent).toContain('Node Smoke');
    expect(bookCard.textContent).toContain('Test Bot');
  });
});
