// Storage that fails to read, as a browser's does: shared by the specs that check
// what is shown when a record cannot be read (#174, #374).

/** From the next load on, every IndexedDB read of a key that which
    names fails, as a read does when storage is failing: its request
    fires error. which is 'lib', 'set', or 'annotations' (a book's "a"
    record). The keys are kept in localStorage, so a reload keeps them
    failing until healReads */
export async function failReads(page, which) {
  await page.evaluate(which => localStorage.setItem('failReads', which), which);
}

export async function healReads(page) {
  await page.evaluate(() => localStorage.removeItem('failReads'));
}

/** The library's records are read together, by their prefix (#354).
    From the next load on, that read fails with a DOMException named
    name, as a browser's does (bridge reads the name, #374): for the next
    times reads (every one when times is -1). The count is kept in
    localStorage, so a reload carries it on */
export async function failLibrary(page, name, times = -1) {
  await page.evaluate(([name, times]) => {
    localStorage.setItem('failReads', 'lib');
    localStorage.setItem('failName', name);
    localStorage.setItem('failLeft', String(times));
  }, [name, times]);
}

/** Installed before every load: a read of a failing key errs */
export async function stubReads(page) {
  await page.addInitScript(() => {
    const failing = key => {
      const which = localStorage.getItem('failReads');
      if (!which || typeof key !== 'string') return false;
      if (which === 'annotations') return key.length === 15 && key[0] === 'a';
      return key === which;
    };
    const erring = () => {
      const request = { result: undefined, error: new DOMException('read failed', 'UnknownError') };
      setTimeout(() => { if (request.onerror) request.onerror(new Event('error')); });
      return request;
    };
    const get = IDBObjectStore.prototype.get;
    IDBObjectStore.prototype.get = function (key) {
      return failing(key) ? erring() : get.call(this, key);
    };
    // the library's records are read together, by their prefix (#354)
    const getAll = IDBObjectStore.prototype.getAll;
    IDBObjectStore.prototype.getAll = function (range, ...rest) {
      const lower = range && typeof range.lower === 'string' ? range.lower : '';
      if (lower.startsWith('library/') && localStorage.getItem('failReads') === 'lib') {
        const left = Number(localStorage.getItem('failLeft') ?? '-1');
        if (left !== 0) {
          if (left > 0) localStorage.setItem('failLeft', String(left - 1));
          // the browser's own error, named as the specification names it
          throw new DOMException('the library could not be read', localStorage.getItem('failName') ?? 'UnknownError');
        }
      }
      return getAll.call(this, range, ...rest);
    };
  });
}
