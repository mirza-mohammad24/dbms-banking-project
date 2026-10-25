import { useCallback, useEffect, useState } from "react";
import { api, apiError } from "./api";

export function useResource(path, revision = 0, poll = 0) {
  const [state, setState] = useState({
    data: null,
    loading: Boolean(path),
    error: "",
  });
  useEffect(() => {
    if (!path) {
      setState({ data: null, loading: false, error: "" });
      return;
    }
    const controller = new AbortController();
    let fetching = false;
    async function load(initial = false) {
      if (fetching) return;
      fetching = true;
      if (initial)
        setState((previous) => ({ ...previous, loading: true, error: "" }));
      try {
        const { data } = await api.get(path, { signal: controller.signal });
        if (!controller.signal.aborted)
          setState({ data, loading: false, error: "" });
      } catch (error) {
        if (error.code !== "ERR_CANCELED")
          setState((previous) => ({
            ...previous,
            loading: false,
            error: apiError(error),
          }));
      } finally {
        fetching = false;
      }
    }
    load(true);
    const timer = poll
      ? setInterval(() => {
          if (!document.hidden) load();
        }, poll)
      : null;
    return () => {
      controller.abort();
      if (timer) clearInterval(timer);
    };
  }, [path, revision, poll]);
  return state;
}

export function useWorkflow() {
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState(null);
  const refresh = useCallback(() => setRevision((value) => value + 1), []);
  const closeToast = useCallback(() => setToast(null), []);
  async function run(path, payload, method = "post") {
    setBusy(true);
    try {
      const { data } = await api.request({ url: path, method, data: payload });
      setToast({
        type: "success",
        message: data.message || "Transaction committed successfully.",
      });
      refresh();
      return data;
    } catch (error) {
      setToast({ type: "error", message: apiError(error) });
      return null;
    } finally {
      setBusy(false);
    }
  }
  return { revision, refresh, busy, toast, closeToast, run };
}

export function useDebounced(value, delay = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}
