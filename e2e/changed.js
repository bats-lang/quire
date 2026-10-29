/** Waiting for a directory to change instead of for a time (quire#985, keyword: changed). */
import { existsSync, watch } from 'node:fs';
import { dirname } from 'node:path';

/** Resolves when something in `directory` changes (a file made, written or removed), when an event of `also` is emitted
    (`[[emitter, 'exit'], ...]`: what else ends the wait, as a child that ends), or at the limit `ms`, which is the
    caller's budget and no part of what is waited for: the caller looks again at what it waits for. */
export function directoryChanged(directory, ms, also = []) {
  return new Promise((resolve) => {
    let limit = null;
    let watcher = null;
    const heard = also.map(([emitter, name]) => { emitter.once(name, finish); return [emitter, name]; });
    function finish() {
      clearTimeout(limit);
      if (watcher) watcher.close();
      for (const [emitter, name] of heard) emitter.off(name, finish);
      resolve();
    }
    try { watcher = watch(directory, finish); } catch (failure) { /* a directory that cannot be watched is looked at again at the limit */ }
    limit = setTimeout(() => { finish(); }, Math.max(ms, 0));
  });
}

/** Resolves true when the file exists (now, or when it is made), false at the limit `ms`: the caller's budget. The directory is
    watched before the file is looked for, so a file made between the two is not missed. */
export function fileAppears(path, ms) {
  return new Promise((resolve) => {
    let limit = null;
    let watcher = null;
    const finish = (found) => {
      clearTimeout(limit);
      if (watcher) watcher.close();
      resolve(found);
    };
    try { watcher = watch(dirname(path), () => { if (existsSync(path)) finish(true); }); } catch (failure) { /* a directory that cannot be watched is looked at at the limit */ }
    limit = setTimeout(() => { finish(existsSync(path)); }, Math.max(ms, 0));
    if (existsSync(path)) finish(true);
  });
}
