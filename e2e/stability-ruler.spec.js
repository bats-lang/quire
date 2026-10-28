// stability.spec.js with the reading ruler on (#566): the same tests, unchanged, each book opened with the Lightbox ruler chosen.
// ruler-on.js is imported first, so the choice is made before the tests are registered; this file and stability.spec.js are
// in different groups (tests/groups.json), each run in a process of its own, so neither finds the other's module loaded.
import { test } from './fixtures.js'; // global-setup.js asks every spec for the stall watch: the tests are stability.spec.js's own
import './ruler-on.js';
import './stability.spec.js';
