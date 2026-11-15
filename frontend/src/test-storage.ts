// Node 25+ définit un globalThis.localStorage inutilisable sans --localstorage-file, qui masque celui de jsdom.
// Les tests unitaires utilisent un stockage en mémoire.
export function installMemoryStorage(): void {
  const data = new Map<string, string>();
  const storage: Storage = {
    get length() { return data.size; },
    clear: () => data.clear(),
    getItem: (k) => data.get(k) ?? null,
    key: (i) => [...data.keys()][i] ?? null,
    removeItem: (k) => { data.delete(k); },
    setItem: (k, v) => { data.set(k, String(v)); },
  };
  Object.defineProperty(globalThis, 'localStorage', { value: storage, configurable: true });
}
