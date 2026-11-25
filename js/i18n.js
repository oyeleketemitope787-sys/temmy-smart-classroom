/**
 * Temmy Smart Classroom — shared localization runtime
 * ICU engine: intl-messageformat@12.1.4 (pinned ESM dependency)
 * Language resources: /locales/{BCP47}/{namespace}.json
 */
import { IntlMessageFormat } from "https://esm.sh/intl-messageformat@12.1.4";

const FALLBACK_LANGUAGE = "en";
const STORAGE_KEY = "temmy.interfaceLanguage.v1";
const DEBUG = new URLSearchParams(window.location.search).get("i18nDebug") === "1";

export const LANGUAGE_REGISTRY = Object.freeze({
  en:      { tag: "en",      nativeName: "English",              direction: "ltr" },
  ar:      { tag: "ar",      nativeName: "العربية",              direction: "rtl" },
  fr:      { tag: "fr",      nativeName: "Français",             direction: "ltr" },
  es:      { tag: "es",      nativeName: "Español",              direction: "ltr" },
  pt:      { tag: "pt",      nativeName: "Português",            direction: "ltr" },
  hi:      { tag: "hi",      nativeName: "हिन्दी",                 direction: "ltr" },
  ur:      { tag: "ur",      nativeName: "اردو",                  direction: "rtl" },
  sw:      { tag: "sw",      nativeName: "Kiswahili",            direction: "ltr" },
  "zh-Hans": { tag: "zh-Hans", nativeName: "简体中文",            direction: "ltr" }
});

const bundles = new Map();
const compiledMessages = new Map();
let activeLanguage = FALLBACK_LANGUAGE;
let initialized = false;

function validLanguage(tag) {
  return Object.prototype.hasOwnProperty.call(LANGUAGE_REGISTRY, tag);
}

function getPath(object, path) {
  return path.split(".").reduce((value, part) => (
    value && Object.prototype.hasOwnProperty.call(value, part) ? value[part] : undefined
  ), object);
}

async function loadBundle(language, namespace) {
  const cacheKey = language + ":" + namespace;
  if (bundles.has(cacheKey)) return bundles.get(cacheKey);

  const url = new URL(`../locales/${encodeURIComponent(language)}/${encodeURIComponent(namespace)}.json`, import.meta.url);
  const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-cache" });
  if (!response.ok) throw new Error(`Localization resource unavailable: ${language}/${namespace} (${response.status})`);

  const bundle = await response.json();
  if (!bundle || bundle.$meta?.language !== language || bundle.$meta?.namespace !== namespace) {
    throw new Error(`Localization resource metadata mismatch: ${language}/${namespace}`);
  }
  bundles.set(cacheKey, bundle);
  return bundle;
}

async function ensureNamespace(namespace) {
  const requests = [loadBundle(FALLBACK_LANGUAGE, namespace)];
  if (activeLanguage !== FALLBACK_LANGUAGE) requests.push(loadBundle(activeLanguage, namespace));
  const results = await Promise.allSettled(requests);
  if (results[0].status !== "fulfilled") throw results[0].reason;
  if (activeLanguage !== FALLBACK_LANGUAGE && results[1].status === "rejected") {
    if (DEBUG) console.warn("[Temmy i18n] Active language bundle unavailable; using English.", results[1].reason);
  }
  return true;
}

function resolveMessage(namespace, key) {
  const active = bundles.get(activeLanguage + ":" + namespace);
  const english = bundles.get(FALLBACK_LANGUAGE + ":" + namespace);
  const translated = active && getPath(active, key);
  if (typeof translated === "string" && translated.length) return { message: translated, language: activeLanguage };
  const fallback = english && getPath(english, key);
  if (typeof fallback === "string" && fallback.length) {
    if (activeLanguage !== FALLBACK_LANGUAGE && DEBUG) {
      console.warn(`[Temmy i18n] Missing translation: ${activeLanguage}/${namespace}.${key}`);
    }
    return { message: fallback, language: FALLBACK_LANGUAGE };
  }
  if (DEBUG) console.warn(`[Temmy i18n] Missing localization key: ${namespace}.${key}`);
  return { message: "Text unavailable", language: FALLBACK_LANGUAGE };
}

export function t(key, values = {}, namespace = "common") {
  const resolved = resolveMessage(namespace, key);
  try {
    const cacheKey = resolved.language + ":" + namespace + ":" + key + ":" + resolved.message;
    let formatter = compiledMessages.get(cacheKey);
    if (!formatter) {
      formatter = new IntlMessageFormat(resolved.message, resolved.language);
      compiledMessages.set(cacheKey, formatter);
    }
    const output = formatter.format(values);
    return Array.isArray(output) ? output.join("") : String(output);
  } catch (error) {
    if (DEBUG) console.error("[Temmy i18n] Message formatting failed:", error);
    return resolved.message;
  }
}

export async function loadNamespaces(namespaces = ["common"]) {
  const unique = [...new Set(namespaces)];
  await Promise.all(unique.map(ensureNamespace));
  return unique;
}

export async function setLanguage(language) {
  if (!validLanguage(language)) throw new RangeError("Unsupported interface language.");
  const previous = activeLanguage;
  activeLanguage = language;
  try {
    await loadNamespaces(["common"]);
    localStorage.setItem(STORAGE_KEY, language);
    applyDocumentLanguage();
    window.dispatchEvent(new CustomEvent("temmy:language-changed", {
      detail: { language, previousLanguage: previous, direction: LANGUAGE_REGISTRY[language].direction }
    }));
    return language;
  } catch (error) {
    activeLanguage = previous;
    throw error;
  }
}

export function getLanguage() {
  return activeLanguage;
}

export function getDirection() {
  return LANGUAGE_REGISTRY[activeLanguage].direction;
}

export function formatNumber(value, options = {}) {
  return new Intl.NumberFormat(activeLanguage, options).format(value);
}

export function formatDate(value, options = {}) {
  return new Intl.DateTimeFormat(activeLanguage, options).format(value instanceof Date ? value : new Date(value));
}

export function applyDocumentLanguage() {
  document.documentElement.lang = activeLanguage;
  document.documentElement.dir = getDirection();
  document.documentElement.dataset.interfaceLanguage = activeLanguage;
}

export async function initLocalization(namespaces = ["common"]) {
  if (initialized) {
    await loadNamespaces(namespaces);
    return activeLanguage;
  }

  let requested = FALLBACK_LANGUAGE;
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && validLanguage(saved)) requested = saved;
  } catch (error) {
    if (DEBUG) console.warn("[Temmy i18n] Browser storage is unavailable.", error);
  }

  activeLanguage = requested;
  await loadNamespaces(namespaces);
  applyDocumentLanguage();
  initialized = true;
  return activeLanguage;
}

const api = Object.freeze({
  LANGUAGE_REGISTRY,
  t,
  loadNamespaces,
  setLanguage,
  getLanguage,
  getDirection,
  formatNumber,
  formatDate,
  applyDocumentLanguage,
  initLocalization
});

window.TemmyI18n = api;
initLocalization().then(language => {
  window.dispatchEvent(new CustomEvent("temmy:i18n-ready", { detail: { language } }));
}).catch(error => {
  console.error("[Temmy i18n] Initialization failed; the classroom will continue in its existing language.", error);
  window.dispatchEvent(new CustomEvent("temmy:i18n-error", { detail: { message: "Localization could not be initialized." } }));
});
