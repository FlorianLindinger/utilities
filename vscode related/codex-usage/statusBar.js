"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.StatusBar = void 0;
exports.createUsageSummaryItems = createUsageSummaryItems;
exports.createMoreInformationItems = createMoreInformationItems;
exports.isMoreInformationItem = isMoreInformationItem;
const vscode = __importStar(require("vscode"));
const format_1 = require("./format");
// Codex only reports the windows that apply to the account: some plans get a
// 5h + weekly pair, others a single weekly (or monthly) window. Render what
// is present instead of assuming primary=5h and secondary=weekly.
function collectWindows(snapshot) {
    const out = [];
    const slots = ["primary", "secondary"];
    for (const slot of slots) {
        const window = snapshot.rateLimits[slot];
        if (!window)
            continue;
        out.push({
            slot,
            window,
            shortLabel: (0, format_1.windowShortLabel)(window, slot),
            longLabel: (0, format_1.windowLongLabel)(window, slot),
        });
    }
    return out;
}
function windowIcon(shortLabel) {
    return shortLabel === "5h" || shortLabel === "Usage" ? "$(pulse)" : "$(calendar)";
}
const TEXT_BAR_WIDTH = 16;
const SVG_BAR_WIDTH = 180;
const SVG_BAR_HEIGHT = 10;
const SVG_BAR_RADIUS = 5;
const USAGE_COLOR_DEFAULT = "#73c991";
const USAGE_COLOR_WARNING = "#e5c07b";
const USAGE_COLOR_ORANGE = "#e9953a";
const USAGE_COLOR_ERROR = "#f14c4c";
const STATUS_BAR_PRIORITY = 100;
class StatusBar {
    constructor(side = "left") {
        this.side = side;
        this.items = [];
    }
    createItem(side, index) {
        const alignment = side === "right" ? vscode.StatusBarAlignment.Right : vscode.StatusBarAlignment.Left;
        const priority = STATUS_BAR_PRIORITY + (side === "right" ? index : -index);
        const item = vscode.window.createStatusBarItem(alignment, priority);
        item.command = "codexUsage.showUsage";
        return item;
    }
    ensureAlignment(side) {
        if (side === this.side)
            return false;
        this.dispose();
        this.side = side;
        return true;
    }
    dispose() {
        this.items.forEach(item => item.dispose());
        this.items = [];
    }
    update(snapshot, options = {}) {
        const compact = options.compact ?? false;
        const windows = snapshot ? collectWindows(snapshot) : [];
        const count = Math.max(1, compact ? 1 : windows.length);
        while (this.items.length < count)
            this.items.push(this.createItem(this.side, this.items.length));
        while (this.items.length > count)
            this.items.pop().dispose();
        const tooltip = snapshot ? renderUsageTooltip(snapshot, windows, options.note)
            : "No Codex usage data. Start a Codex session or run 'codex login'.";
        const top = windows.reduce((best, w) => !best || (w.window.used_percent ?? 0) > (best.window.used_percent ?? 0) ? w : best, null);
        this.items.forEach((item, index) => {
            const w = compact ? top : windows[index];
            item.name = w ? `Codex ${w.longLabel} usage` : "Codex usage";
            if (!w) {
                item.text = compact ? "$(codex-logo) ?" : "$(codex-logo) Codex ?";
                item.color = undefined;
            } else {
                item.text = compact ? formatCompactText(windows)
                    : `${index === 0 ? "$(codex-logo) Codex " : ""}${formatStatusSegment(w.shortLabel, w.window, snapshot)}`;
                item.color = Number.isFinite(w.window.used_percent) ? getUsageColor(w.window.used_percent) : undefined;
            }
            item.backgroundColor = undefined;
            item.tooltip = tooltip;
            item.show();
        });
    }
}
exports.StatusBar = StatusBar;
function createUsageSummaryItems(snapshot) {
    const windows = collectWindows(snapshot);
    const items = windows.map((w) => createUsageQuickPickItem(`${windowIcon(w.shortLabel)} ${w.longLabel}`, w.window, snapshot));
    if (items.length === 0) {
        items.push({
            label: "$(pulse) Rate limits",
            detail: "No rate-limit windows reported by Codex.",
        });
    }
    items.push({
        label: "$(info) More information",
        detail: "Captured time, source file, and rate-limit window lengths.",
    });
    return items;
}
function createMoreInformationItems(snapshot, note) {
    const items = [
        {
            label: snapshot.source === "api" ? "$(cloud) Source" : "$(file) Source",
            detail: `${snapshot.source === "api" ? "Live API" : "Rollout file"} — ${snapshot.sourceFile}`,
        },
        {
            label: "$(clock) Captured",
            detail: snapshot.capturedAt.toLocaleString(),
        },
    ];
    if (note) {
        items.push({ label: "$(info) Status", detail: note });
    }
    for (const w of collectWindows(snapshot)) {
        items.push({
            label: `${windowIcon(w.shortLabel)} ${w.longLabel} window`,
            detail: formatWindowLength(w.window),
        });
    }
    if (snapshot.rateLimits.plan_type) {
        items.push({
            label: "$(account) Plan",
            detail: snapshot.rateLimits.plan_type,
        });
    }
    if (snapshot.rateLimits.normal_model_slug) {
        items.push({
            label: "$(sync) Reserve for",
            detail: snapshot.rateLimits.normal_model_slug,
        });
    }
    const credits = formatCredits(snapshot.rateLimits.credits ?? null);
    if (credits) {
        items.push({
            label: "$(credit-card) Credits",
            detail: credits,
        });
    }
    const individualLimit = formatIndividualLimit(snapshot.rateLimits.individual_limit ?? null);
    if (individualLimit) {
        items.push({
            label: "$(law) Spend limit",
            detail: individualLimit,
        });
    }
    if (snapshot.rateLimits.spend_control_reached) {
        items.push({
            label: "$(warning) Spend control reached",
            detail: formatRateLimitReachedType(snapshot.rateLimits.rate_limit_reached_type ?? null),
        });
    }
    if (snapshot.rateLimits.limit_reached) {
        items.push({
            label: "$(warning) Rate limit reached",
            detail: formatRateLimitReachedType(snapshot.rateLimits.rate_limit_reached_type ?? null),
        });
    }
    const resetCredits = formatResetCredits(snapshot.rateLimits.rate_limit_reset_credits ?? null);
    if (resetCredits) {
        items.push({
            label: "$(history) Limit reset credits",
            detail: resetCredits,
        });
    }
    for (const limit of snapshot.rateLimits.additional_limits ?? []) {
        const detail = formatAdditionalLimit(limit, snapshot.capturedAt);
        if (detail) {
            items.push({ label: `$(pulse) ${limit.limit_name}`, detail });
        }
    }
    return items;
}
// Renders a per-feature limit (e.g. from `additional_rate_limits`) as a single
// line combining its primary/secondary windows, matching the compact style of
// `formatStatusSegment` since these don't get their own status bar segment.
function formatAdditionalLimit(limit, capturedAt) {
    const parts = [];
    for (const [slot, window] of [
        ["primary", limit.primary],
        ["secondary", limit.secondary],
    ]) {
        if (!window)
            continue;
        const reset = (0, format_1.getResetDisplay)(window, capturedAt);
        const resetDuration = reset ? (0, format_1.formatDuration)(reset.secondsRemaining) : "unknown";
        parts.push(`${(0, format_1.windowShortLabel)(window, slot)} ${(0, format_1.formatPercent)(window.used_percent)} · ${resetDuration}`);
    }
    return parts.length > 0 ? parts.join(" / ") : null;
}
function formatCredits(credits) {
    if (!credits)
        return null;
    const overage = credits.overage_limit_reached ? " — overage limit reached" : "";
    if (credits.unlimited)
        return `Unlimited${overage}`;
    if (!credits.has_credits)
        return `No credits${overage}`;
    return `${credits.balance ? `Balance: ${credits.balance}` : "Available"}${overage}`;
}
function formatIndividualLimit(limit) {
    if (!limit)
        return null;
    return `${limit.used} / ${limit.limit} (${limit.remaining_percent}% remaining)`;
}
function formatResetCredits(credits) {
    if (!credits || credits.available_count <= 0)
        return null;
    const applicable = credits.applicable_available_count;
    const suffix = typeof applicable === "number" ? ` (${applicable} applicable to the current windows)` : "";
    return `${credits.available_count} available${suffix}`;
}
function formatRateLimitReachedType(type) {
    if (!type)
        return "Limit reached";
    return type
        .split("_")
        .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
        .join(" ");
}
function isMoreInformationItem(item) {
    return item?.label === "$(info) More information";
}
function renderUsageTooltip(snapshot, windows, note) {
    const md = new vscode.MarkdownString(undefined, true);
    md.isTrusted = { enabledCommands: ["codexUsage.showMoreInformation"] };
    md.appendMarkdown(`**Codex usage** · ${sourceLabel(snapshot)}\n\n`);
    if (windows.length === 0) {
        md.appendMarkdown("No rate-limit windows reported\n");
    }
    else {
        windows.forEach((w, i) => {
            if (i > 0)
                md.appendMarkdown("\n\n");
            appendUsageWindow(md, w.longLabel, w.window, snapshot);
        });
    }
    if (note) {
        md.appendMarkdown(`\n\n$(info) ${escapeMarkdownAltText(note)}`);
    }
    md.appendMarkdown("\n\n[More information](command:codexUsage.showMoreInformation)");
    return md;
}
// Icon + label describing where the snapshot came from.
function sourceLabel(snapshot) {
    return snapshot.source === "api" ? "$(cloud) Live API" : "$(file) Rollout file";
}
// Compact chip: icon + the single highest-used window percent, so the number
// always matches the warning/error background colour.
function formatCompactText(windows) {
    const top = windows.reduce((a, b) => (b.window.used_percent ?? 0) > (a.window.used_percent ?? 0) ? b : a);
    return `$(codex-logo) ${(0, format_1.formatPercent)(clampPercent(top.window.used_percent), false)}`;
}
function appendUsageWindow(md, label, window, snapshot) {
    md.appendMarkdown(`**${label}**\n\n`);
    const pct = clampPercent(window.used_percent);
    md.appendMarkdown(`**${(0, format_1.formatPercent)(pct)}**\n\n`);
    md.appendMarkdown(`${formatSvgBar(pct, `${label} usage ${(0, format_1.formatPercent)(pct)}`)}\n\n`);
    md.appendMarkdown(`Resets ${formatResetDate(window, snapshot)}`);
}
function createUsageQuickPickItem(label, window, snapshot) {
    const pct = clampPercent(window.used_percent);
    return {
        label: `${label} ${(0, format_1.formatPercent)(pct)}`,
        description: formatTextBar(pct),
        detail: `Resets ${formatResetDate(window, snapshot)}`,
    };
}
function formatStatusSegment(label, window, snapshot) {
    const reset = (0, format_1.getResetDisplay)(window, snapshot.capturedAt);
    const resetDuration = reset ? (0, format_1.formatDuration)(reset.secondsRemaining) : "unknown";
    return `${label} ${(0, format_1.formatPercent)(window.used_percent, false)} · ${resetDuration}`;
}
function formatWindowLength(window) {
    if (!window)
        return "No data";
    if (typeof window.window_minutes !== "number" || !Number.isFinite(window.window_minutes)) {
        return "Unknown";
    }
    return `${window.window_minutes} min`;
}
function formatResetDate(window, snapshot) {
    const reset = (0, format_1.getResetDisplay)(window, snapshot.capturedAt);
    return reset ? reset.resetAt.toLocaleString() : "unknown";
}
function formatTextBar(percent) {
    const pct = clampPercent(percent);
    const shown = (0, format_1.displayPercent)(pct);
    const filled = shown > 0 ? Math.max(1, Math.round((shown / 100) * TEXT_BAR_WIDTH)) : 0;
    return `${getUsageIcon(pct)} ${"█".repeat(filled)}${"░".repeat(TEXT_BAR_WIDTH - filled)}`;
}
function formatSvgBar(percent, altText) {
    const pct = clampPercent(percent);
    const fillWidth = Math.round(((0, format_1.displayPercent)(pct) / 100) * SVG_BAR_WIDTH);
    const fillColor = getUsageColor(pct);
    const svg = [
        `<svg xmlns="http://www.w3.org/2000/svg" width="${SVG_BAR_WIDTH}" height="${SVG_BAR_HEIGHT}" viewBox="0 0 ${SVG_BAR_WIDTH} ${SVG_BAR_HEIGHT}">`,
        `<rect width="${SVG_BAR_WIDTH}" height="${SVG_BAR_HEIGHT}" rx="${SVG_BAR_RADIUS}" fill="#2d2d30"/>`,
        `<rect width="${fillWidth}" height="${SVG_BAR_HEIGHT}" rx="${SVG_BAR_RADIUS}" fill="${fillColor}"/>`,
        `<rect x="0.5" y="0.5" width="${SVG_BAR_WIDTH - 1}" height="${SVG_BAR_HEIGHT - 1}" rx="${SVG_BAR_RADIUS - 0.5}" fill="none" stroke="#6e7681" stroke-opacity="0.8"/>`,
        "</svg>",
    ].join("");
    const encoded = Buffer.from(svg).toString("base64");
    return `![${escapeMarkdownAltText(altText)}](data:image/svg+xml;base64,${encoded})`;
}
function escapeMarkdownAltText(text) {
    return text.replace(/[[\]\\]/g, "\\$&");
}
function getUsageColor(percent) {
    if (percent >= 75) return USAGE_COLOR_ERROR;
    if (percent >= 50) return USAGE_COLOR_ORANGE;
    if (percent >= 25) return USAGE_COLOR_WARNING;
    return USAGE_COLOR_DEFAULT;
}
function getUsageIcon(percent) {
    if (percent >= 75) return "??";
    if (percent >= 50) return "??";
    if (percent >= 25) return "??";
    return "??";
}
function clampPercent(percent) {
    if (!Number.isFinite(percent))
        return 0;
    return Math.min(100, Math.max(0, percent));
}
//# sourceMappingURL=statusBar.js.map