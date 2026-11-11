import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
let fileConfig = {};
try {
  fileConfig = JSON.parse(readFileSync(path.join(here, 'owner-alerts.config.json'), 'utf8'));
} catch (error) {
  console.warn('[OwnerAlerts] Configuration file unavailable:', error?.message || error);
}

const WEBHOOK_URL = process.env.HEARTHFALL_OWNER_ALERT_WEBHOOK_URL || fileConfig.webhookUrl || '';
const ALLOWED_EVENTS = new Set(fileConfig.events || []);
const recentEvents = new Map();

function trimValue(value, limit = 500) {
  if (value === null || value === undefined) return undefined;
  return String(value).slice(0, limit);
}

function sanitizeContext(context = {}) {
  if (!context || typeof context !== 'object' || Array.isArray(context)) return {};
  return Object.fromEntries(Object.entries(context).slice(0, 16).map(([key, value]) => [
    trimValue(key, 80),
    trimValue(typeof value === 'object' ? JSON.stringify(value) : value, 300),
  ]));
}

export async function emitOwnerEvent({ eventType, severity = 'info', title, message, context = {}, user = null } = {}) {
  if (!WEBHOOK_URL || !ALLOWED_EVENTS.has(eventType)) return { delivered: false, skipped: true };

  const safeEvent = {
    eventType: trimValue(eventType, 64),
    severity: trimValue(severity, 24),
    title: trimValue(title || eventType, 160),
    message: trimValue(message || '', 600),
    context: sanitizeContext(context),
    user: user ? {
      id: trimValue(user.id, 80),
      name: trimValue(user.name, 120),
      loginMethod: trimValue(user.loginMethod, 80),
    } : undefined,
    occurredAt: new Date().toISOString(),
  };

  const dedupeKey = `${safeEvent.eventType}:${safeEvent.title}:${safeEvent.message}`;
  const lastSent = recentEvents.get(dedupeKey) || 0;
  if (Date.now() - lastSent < 30_000) return { delivered: false, deduplicated: true };
  recentEvents.set(dedupeKey, Date.now());

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ payload: safeEvent }),
      signal: controller.signal,
    });
    if (!response.ok) {
      console.warn(`[OwnerAlerts] Webhook returned ${response.status} for ${safeEvent.eventType}`);
      return { delivered: false, status: response.status };
    }
    return { delivered: true };
  } catch (error) {
    console.warn(`[OwnerAlerts] Failed to deliver ${safeEvent.eventType}:`, error?.message || error);
    return { delivered: false, error: error?.message || 'webhook_failed' };
  } finally {
    clearTimeout(timeout);
  }
}
