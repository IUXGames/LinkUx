/*!
 * DocShell v1.0.0
 * ─────────────────────────────────────────────────────────────────────────────
 * A modular, plug-and-use documentation system.
 * Parses Markdown files that use  <!-- doc-shell:page slug="..." -->  markers
 * to split content into independent, navigable pages.
 *
 * Optional dependencies (loaded via CDN or bundler):
 *   · marked.js  v4.x  → https://cdn.jsdelivr.net/npm/marked@4/marked.min.js
 *   · highlight.js     → https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js
 *
 * Author : DocShell contributors
 * License: MIT
 */

(function (global, factory) {
  if (typeof module === 'object' && typeof module.exports === 'object') {
    module.exports = factory();
  } else {
    global.DocShell = factory();
  }
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';

  // ─── Constants ───────────────────────────────────────────────────────────────

  const VERSION       = '1.0.0';
  const DEFAULT_PFX   = 'ds-';
  const PAGE_RE_SRC   = /<!--\s*doc-shell:page\s+slug="([^"]+)"\s*-->/g;

  // ─── Small utilities ─────────────────────────────────────────────────────────

  function escHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function escAttr(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#x27;');
  }

  function slugify(text) {
    return String(text)
      .toLowerCase()
      .replace(/[^\w\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
  }

  /** Grab the text of the first markdown heading in a chunk */
  function firstHeading(md) {
    const m = md.match(/^#{1,6}\s+(.+)$/m);
    return m ? m[1].replace(/[*_`[\]]/g, '').trim() : null;
  }

  /** Strip markdown syntax to plain searchable text */
  function mdToPlain(md) {
    return md
      .replace(/<!--[\s\S]*?-->/g, '')       // html comments
      .replace(/```[\s\S]*?```/g, '')         // fenced code
      .replace(/`([^`]+)`/g, '$1')            // inline code
      .replace(/!\[([^\]]*)\]\([^)]*\)/g, '') // images
      .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')// links
      .replace(/\*\*(.+?)\*\*/g, '$1')        // bold **
      .replace(/__(.+?)__/g, '$1')            // bold __
      .replace(/\*(.+?)\*/g, '$1')            // italic *
      .replace(/_(.+?)_/g, '$1')              // italic _
      .replace(/~~(.+?)~~/g, '$1')            // strike
      .replace(/^#{1,6}\s+/gm, '')            // heading hashes
      .replace(/^\|.+\|$/gm, ' ')             // table rows
      .replace(/^[-*+]\s+/gm, '')             // unordered lists
      .replace(/^\d+\.\s+/gm, '')             // ordered lists
      .replace(/^>\s+/gm, '')                 // blockquotes
      .replace(/^-{3,}$/gm, '')               // hr
      .replace(/\s+/g, ' ')
      .trim();
  }

  // ─── Marked.js custom renderer ───────────────────────────────────────────────
  //
  //  All HTML elements produced by the renderer carry a  ds-*  class
  //  (or whatever prefix the user configures). No colors, no fonts —
  //  just semantic hooks ready for any custom stylesheet.
  //
  //  Compatibility layer handles both:
  //    · marked v4 — methods receive plain arguments  (text, level, ...)
  //    · marked v5+ — methods receive a token object  ({ text, depth, ... })

  function buildRenderer(p) {
    if (typeof window === 'undefined' || !window.marked) return null;

    const r = new window.marked.Renderer();

    // Normalize: if the first argument is an object (v5+ token), extract fields.
    function norm(args, fields) {
      if (typeof args[0] === 'object' && args[0] !== null) {
        const tok = args[0];
        return fields.map(f => tok[f]);
      }
      return args;
    }

    r.heading = function (...a) {
      let [text, level] = norm(a, ['text', 'depth']);
      // marked v5 already processes inline tokens inside text; v4 passes raw html
      const id = slugify(text.replace(/<[^>]+>/g, ''));
      return `<h${level} class="${p}h${level}" id="${id}">${text}</h${level}>\n`;
    };

    r.paragraph = function (...a) {
      const [text] = norm(a, ['text']);
      return `<p class="${p}p">${text}</p>\n`;
    };

    r.list = function (...a) {
      let [body, ordered, start] = norm(a, ['body', 'ordered', 'start']);
      const tag  = ordered ? 'ol' : 'ul';
      const attr = ordered && start !== 1 ? ` start="${start}"` : '';
      return `<${tag} class="${p}${tag}"${attr}>${body}</${tag}>\n`;
    };

    r.listitem = function (...a) {
      const [text] = norm(a, ['text']);
      return `<li class="${p}li">${text}</li>\n`;
    };

    r.table = function (...a) {
      const [header, body] = norm(a, ['header', 'body']);
      return (
        `<div class="${p}table-wrapper">` +
          `<table class="${p}table">` +
            `<thead class="${p}thead">${header}</thead>` +
            `<tbody class="${p}tbody">${body}</tbody>` +
          `</table>` +
        `</div>\n`
      );
    };

    r.tablerow = function (...a) {
      const [content] = norm(a, ['text']);
      return `<tr class="${p}tr">${content}</tr>\n`;
    };

    r.tablecell = function (...a) {
      let [content, flags] = norm(a, ['text', 'flags']);
      // v5 puts header/align directly on token
      if (typeof a[0] === 'object' && 'header' in a[0]) {
        flags = { header: a[0].header, align: a[0].align };
      }
      const tag   = flags?.header ? 'th' : 'td';
      const align = flags?.align  ? ` style="text-align:${flags.align}"` : '';
      return `<${tag} class="${p}${tag}"${align}>${content}</${tag}>\n`;
    };

    r.code = function (...a) {
      let [code, lang] = norm(a, ['text', 'lang']);
      lang = lang || 'plaintext';
      return (
        `<div class="${p}code-block-wrapper" data-lang="${escAttr(lang)}">` +
          `<div class="${p}code-block-header">` +
            `<span class="${p}code-lang">${escHtml(lang)}</span>` +
            `<button class="${p}code-copy-btn" type="button" data-code="${escAttr(code)}"></button>` +
          `</div>` +
          `<pre class="${p}pre">` +
            `<code class="${p}code-block language-${escAttr(lang)}" data-lang="${escAttr(lang)}">${escHtml(code)}</code>` +
          `</pre>` +
        `</div>\n`
      );
    };

    r.codespan = function (...a) {
      const [code] = norm(a, ['text']);
      return `<code class="${p}code-inline">${escHtml(code)}</code>`;
    };

    r.blockquote = function (...a) {
      const [quote] = norm(a, ['text']);
      return `<blockquote class="${p}blockquote">${quote}</blockquote>\n`;
    };

    r.hr = function () {
      return `<hr class="${p}hr">\n`;
    };

    r.link = function (...a) {
      let [href, title, text] = norm(a, ['href', 'title', 'text']);
      const t = title ? ` title="${escAttr(title)}"` : '';
      return `<a class="${p}a" href="${href}"${t}>${text}</a>`;
    };

    r.image = function (...a) {
      let [href, title, text] = norm(a, ['href', 'title', 'text']);
      const t   = title ? ` title="${escAttr(title)}"` : '';
      const alt = escAttr(text || '');
      return `<img class="${p}img" src="${href}" alt="${alt}"${t}>`;
    };

    r.strong = function (...a) {
      const [text] = norm(a, ['text']);
      return `<strong class="${p}strong">${text}</strong>`;
    };

    r.em = function (...a) {
      const [text] = norm(a, ['text']);
      return `<em class="${p}em">${text}</em>`;
    };

    r.del = function (...a) {
      const [text] = norm(a, ['text']);
      return `<del class="${p}del">${text}</del>`;
    };

    return r;
  }

  /** Bare fallback when marked.js is absent */
  function fallbackRender(md) {
    return `<pre><code>${escHtml(md)}</code></pre>`;
  }

  // ─── DocShell ────────────────────────────────────────────────────────────────

  class DocShell {
    /**
     * @param {object} options
     * @param {string|Element}   options.container      - CSS selector or DOM element where DocShell renders.
     * @param {object}           [options.langs]        - Language map: { es: 'docs/es.md', en: 'docs/en.md' }
     * @param {string}           [options.defaultLang]  - Initial language key.
     * @param {string}           [options.source]       - Single .md file path (no i18n).
     * @param {string}           [options.prefix]       - CSS class prefix. Default: 'ds-'
     * @param {boolean}          [options.highlight]    - Auto-highlight code blocks via hljs. Default: true
     * @param {string}           [options.copyLabel]    - Label for copy button. Default: 'Copy'
     * @param {string}           [options.copiedLabel]  - Label after copy. Default: 'Copied!'
     * @param {function}         [options.onReady]      - Callback fired after first render.
     * @param {function}         [options.onPageChange] - Callback fired on page navigation.
     * @param {function}         [options.onLangChange] - Callback fired on language change.
     */
    constructor(options = {}) {
      this._opts = {
        container:    options.container    || '#doc-shell',
        langs:        options.langs        || {},
        defaultLang:  options.defaultLang  || null,
        source:       options.source       || null,
        prefix:       options.prefix       || DEFAULT_PFX,
        highlight:    options.highlight    !== false,
        copyLabel:    options.copyLabel    || 'Copy',
        copiedLabel:  options.copiedLabel  || 'Copied!',
        onReady:      options.onReady      || null,
        onPageChange: options.onPageChange || null,
        onLangChange: options.onLangChange || null,
        /** @type {string|Element|null} If set, language switcher + search mount here instead of sidebar */
        headerChrome: options.headerChrome || null,
        navAriaLabel: options.navAriaLabel || 'Documentation',
        langSwitcherAriaLabel: options.langSwitcherAriaLabel || 'Language selector',
      };

      /** @type {Array<{slug:string, title:string, md:string, html:string, text:string}>} */
      this._pages       = [];
      this._lang        = this._opts.defaultLang || Object.keys(this._opts.langs)[0] || null;
      this._currentSlug = null;
      this._el          = null;
      this._listeners   = {};
      this._popHandler  = null;

      this._resolveContainer();
      this._bootstrap();
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Private — setup
    // ════════════════════════════════════════════════════════════════════════════

    _resolveContainer() {
      const c = this._opts.container;
      this._el = (typeof c === 'string') ? document.querySelector(c) : c;
      if (!this._el) throw new Error(`[DocShell] Container not found: "${c}"`);
    }

    async _bootstrap() {
      try {
        await this.load(this._lang);
      } catch (e) {
        console.error('[DocShell] Bootstrap error:', e);
      }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Private — parsing
    // ════════════════════════════════════════════════════════════════════════════

    _parseMd(raw) {
      // Re-create the RegExp to reset lastIndex
      const re = new RegExp(PAGE_RE_SRC.source, 'g');
      const slugs     = [];
      const positions = [];
      let m;

      while ((m = re.exec(raw)) !== null) {
        slugs.push(m[1]);
        positions.push({ markerStart: m.index, contentStart: m.index + m[0].length });
      }

      // No page markers → treat whole file as a single page
      if (slugs.length === 0) {
        return [this._buildPage('main', raw)];
      }

      return slugs.map((slug, i) => {
        const start = positions[i].contentStart;
        const end   = (i + 1 < positions.length) ? positions[i + 1].markerStart : raw.length;
        return this._buildPage(slug, raw.slice(start, end).trim());
      });
    }

    _buildPage(slug, md) {
      const html  = this._renderMd(md);
      const title = firstHeading(md) || slug;
      const text  = mdToPlain(md);
      return { slug, title, md, html, text };
    }

    _renderMd(md) {
      const p = this._opts.prefix;
      if (!window.marked) {
        console.warn('[DocShell] marked.js not found — showing raw markdown. Include marked.js for full rendering.');
        return fallbackRender(md);
      }
      try {
        const renderer = buildRenderer(p);
        // mangle: false → don't obfuscate email links
        // headerIds: false → we set our own IDs via the renderer
        return window.marked.parse(md, { renderer, mangle: false, headerIds: false });
      } catch (e) {
        console.warn('[DocShell] marked.js render error:', e);
        return fallbackRender(md);
      }
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Private — DOM building
    // ════════════════════════════════════════════════════════════════════════════

    _buildLayout() {
      const p     = this._opts.prefix;
      const langs = Object.keys(this._opts.langs);
      const useHeaderChrome = !!this._opts.headerChrome;

      /* ── Language switcher ── */
      const langSwitcher = langs.length > 1
        ? `<div class="${p}lang-switcher" role="group" aria-label="${escAttr(this._opts.langSwitcherAriaLabel)}">` +
            langs.map(l =>
              `<button class="${p}lang-btn${l === this._lang ? ` ${p}lang-btn--active` : ''}" ` +
              `type="button" data-lang="${escAttr(l)}" aria-pressed="${l === this._lang}">${escHtml(l.toUpperCase())}</button>`
            ).join('') +
          `</div>`
        : '';

      const searchSlot = `<div class="${p}search-slot" id="${p}search-slot"></div>`;
      const mobileChrome = useHeaderChrome ? `<div class="${p}mobile-chrome"></div>` : '';
      const sidebarChrome = useHeaderChrome ? '' : (langSwitcher + searchSlot);
      /* Header: búsqueda a la izquierda, selector de idioma a la derecha (junto a GitHub en el layout del sitio) */
      const headerChromeInner = useHeaderChrome ? (searchSlot + langSwitcher) : '';

      /* ── Sidebar nav ── */
      const navItems = this._pages.map(pg =>
        `<li class="${p}nav-item" data-slug="${escAttr(pg.slug)}">` +
          `<a class="${p}nav-link" href="#${escAttr(pg.slug)}">${escHtml(pg.title)}</a>` +
        `</li>`
      ).join('');

      /* ── Page sections ── */
      const sections = this._pages.map(pg =>
        `<section class="${p}page" id="${escAttr(pg.slug)}" data-slug="${escAttr(pg.slug)}" hidden>` +
          `<div class="${p}page-inner">` +
            pg.html +
          `</div>` +
        `</section>`
      ).join('');

      const html = (
        `<div class="${p}root" data-lang="${escAttr(this._lang || '')}">` +

          `<aside class="${p}sidebar">` +
            mobileChrome +
            sidebarChrome +
            `<nav class="${p}nav" aria-label="${escAttr(this._opts.navAriaLabel)}">` +
              `<ul class="${p}nav-list">${navItems}</ul>` +
            `</nav>` +
          `</aside>` +

          `<main class="${p}main" role="main" tabindex="-1">${sections}</main>` +

        `</div>`
      );

      return { html, headerChromeInner };
    }

    _render() {
      const p = this._opts.prefix;
      const layout = this._buildLayout();
      this._el.innerHTML = layout.html;

      if (this._opts.headerChrome && layout.headerChromeInner) {
        const hc = typeof this._opts.headerChrome === 'string'
          ? document.querySelector(this._opts.headerChrome)
          : this._opts.headerChrome;
        if (hc) hc.innerHTML = layout.headerChromeInner;
      }

      this._bindEvents();
      if (this._opts.highlight) this._applyHighlight();

      // Resolve initial page from URL hash, fallback to first page
      const hash   = location.hash.slice(1);
      const target = (hash && this._pages.find(pg => pg.slug === hash))
        ? hash
        : (this._pages[0]?.slug ?? null);

      if (target) this._showPage(target, false);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Private — events & interaction
    // ════════════════════════════════════════════════════════════════════════════

    _bindEvents() {
      const p = this._opts.prefix;

      /* Nav links */
      this._el.querySelectorAll(`.${p}nav-link`).forEach(a => {
        a.addEventListener('click', e => {
          e.preventDefault();
          const slug = a.closest('[data-slug]')?.dataset.slug;
          if (slug) this.navigate(slug);
        });
      });

      /* Language switcher (sidebar y/o header externo #header-doc-chrome) */
      const langRoots = [this._el];
      if (this._opts.headerChrome) {
        const hc = typeof this._opts.headerChrome === 'string'
          ? document.querySelector(this._opts.headerChrome)
          : this._opts.headerChrome;
        if (hc) langRoots.push(hc);
      }
      langRoots.forEach(root => {
        root.querySelectorAll(`.${p}lang-btn`).forEach(btn => {
          btn.addEventListener('click', () => this.setLang(btn.dataset.lang));
        });
      });

      /* Copy buttons — label text set here so it's themeable */
      this._el.querySelectorAll(`.${p}code-copy-btn`).forEach(btn => {
        btn.textContent = this._opts.copyLabel;
        btn.addEventListener('click', () => this._handleCopy(btn));
      });

      /* Browser back / forward */
      if (this._popHandler) window.removeEventListener('popstate', this._popHandler);
      this._popHandler = () => {
        const hash = location.hash.slice(1);
        if (hash && this._pages.find(pg => pg.slug === hash)) {
          this._showPage(hash, false);
        }
      };
      window.addEventListener('popstate', this._popHandler);
    }

    _showPage(slug, pushState = true) {
      const p = this._opts.prefix;

      /* Show/hide sections */
      let found = false;
      this._el.querySelectorAll(`.${p}page`).forEach(sec => {
        const match = sec.dataset.slug === slug;
        if (match) { sec.removeAttribute('hidden'); found = true; }
        else        sec.setAttribute('hidden', '');
      });
      if (!found) return;

      /* Active state on nav links */
      this._el.querySelectorAll(`.${p}nav-item`).forEach(li => {
        li.classList.toggle(`${p}nav-item--active`, li.dataset.slug === slug);
      });
      this._el.querySelectorAll(`.${p}nav-link`).forEach(a => {
        const parentSlug = a.closest('[data-slug]')?.dataset.slug;
        a.classList.toggle(`${p}nav-link--active`, parentSlug === slug);
        a.setAttribute('aria-current', parentSlug === slug ? 'page' : 'false');
      });

      if (pushState) history.pushState(null, '', `#${slug}`);

      this._currentSlug = slug;
      const page = this._pages.find(pg => pg.slug === slug) || null;
      this._emit('pageChange', { slug, page });
      if (this._opts.onPageChange) this._opts.onPageChange(slug, page);
    }

    _applyHighlight() {
      if (typeof window === 'undefined' || !window.hljs) return;
      this._el.querySelectorAll(`.${this._opts.prefix}code-block`).forEach(block => {
        try { window.hljs.highlightElement(block); } catch (_) { /* ignore */ }
      });
    }

    async _handleCopy(btn) {
      const p    = this._opts.prefix;
      const code = btn.dataset.code;
      try {
        await navigator.clipboard.writeText(code);
      } catch (_) {
        /* Clipboard API unavailable — silent fail */
        return;
      }
      const orig = btn.textContent;
      btn.textContent = this._opts.copiedLabel;
      btn.classList.add(`${p}code-copy-btn--copied`);
      setTimeout(() => {
        btn.textContent = orig;
        btn.classList.remove(`${p}code-copy-btn--copied`);
      }, 2000);
    }

    _emit(event, data) {
      (this._listeners[event] || []).forEach(fn => fn(data));
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Public API
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * Load (or reload) a Markdown file.
     * @param {string|null} lang - Language key from the `langs` config map.
     *                            Pass null when using a single `source` file.
     * @returns {Promise<void>}
     */
    async load(lang) {
      const source = lang ? (this._opts.langs[lang] ?? null) : (this._opts.source ?? null);
      if (!source) {
        if (this._opts.source) {
          // single-source mode
          const res = await fetch(this._opts.source);
          if (!res.ok) throw new Error(`[DocShell] HTTP ${res.status} fetching ${this._opts.source}`);
          const raw = await res.text();
          this._pages = this._parseMd(raw);
          this._render();
          this._emit('ready', { lang: null, pages: this._pages });
          if (this._opts.onReady) this._opts.onReady(this);
          return;
        }
        console.error(`[DocShell] No source found for lang "${lang}". Check your config.`);
        return;
      }

      const res = await fetch(source);
      if (!res.ok) throw new Error(`[DocShell] HTTP ${res.status} fetching ${source}`);
      const raw  = await res.text();
      this._pages = this._parseMd(raw);
      this._lang  = lang;
      this._render();
      this._emit('ready', { lang, pages: this._pages });
      if (this._opts.onReady) this._opts.onReady(this);
    }

    /**
     * Navigate to a page by its slug.
     * @param {string} slug
     */
    navigate(slug) {
      this._showPage(slug, true);
    }

    /**
     * Switch to a different language, re-loading the corresponding .md file.
     * @param {string} lang - Language key.
     * @returns {Promise<void>}
     */
    async setLang(lang) {
      if (lang === this._lang) return;
      const prevSlug = this._currentSlug;
      await this.load(lang);
      // Try to restore the same page in the new language
      if (prevSlug && this._pages.find(pg => pg.slug === prevSlug)) {
        this._showPage(prevSlug, false);
      }
      this._emit('langChange', { lang });
      if (this._opts.onLangChange) this._opts.onLangChange(lang);
    }

    /**
     * Re-apply syntax highlighting to all code blocks.
     * Useful if you swap themes dynamically (e.g. light/dark hljs theme).
     */
    rehighlight() {
      this._applyHighlight();
    }

    /**
     * Register an event listener.
     * Events: 'ready' | 'pageChange' | 'langChange'
     * @param {string}   event
     * @param {function} fn
     * @returns {DocShell}
     */
    on(event, fn) {
      if (!this._listeners[event]) this._listeners[event] = [];
      this._listeners[event].push(fn);
      return this;
    }

    /**
     * Remove an event listener.
     * @param {string}   event
     * @param {function} fn
     * @returns {DocShell}
     */
    off(event, fn) {
      if (!this._listeners[event]) return this;
      this._listeners[event] = this._listeners[event].filter(h => h !== fn);
      return this;
    }

    /** @returns {Array} Cloned array of all parsed page objects. */
    getPages() { return [...this._pages]; }

    /** @returns {string|null} Slug of the currently visible page. */
    getCurrentSlug() { return this._currentSlug; }

    /** @returns {string|null} Currently active language key. */
    getCurrentLang() { return this._lang; }

    /** @returns {string[]} All configured language keys. */
    getLangs() { return Object.keys(this._opts.langs); }

    /** @returns {Element} The root container element. */
    getContainer() { return this._el; }

    /**
     * Returns the `<div class="ds-search-slot">` element where
     * DocShellSearch (or a custom search widget) should be mounted.
     * @returns {Element|null}
     */
    getSearchSlot() {
      const id = `${this._opts.prefix}search-slot`.replace(/#/g, '');
      return document.getElementById(id) || this._el?.querySelector(`#${id}`) || null;
    }

    /**
     * Update copy-button labels and refresh visible copy buttons (e.g. after language change).
     * @param {{ copyLabel?: string, copiedLabel?: string }} labels
     */
    setCopyLabels(labels = {}) {
      if (labels.copyLabel != null) this._opts.copyLabel = labels.copyLabel;
      if (labels.copiedLabel != null) this._opts.copiedLabel = labels.copiedLabel;
      const p = this._opts.prefix;
      this._el?.querySelectorAll(`.${p}code-copy-btn`).forEach(btn => {
        if (btn.classList.contains(`${p}code-copy-btn--copied`)) return;
        btn.textContent = this._opts.copyLabel;
      });
    }

    /**
     * @param {{ navAriaLabel?: string }} opts
     */
    setChromeStrings(opts = {}) {
      if (opts.navAriaLabel != null) {
        this._opts.navAriaLabel = opts.navAriaLabel;
        const nav = this._el?.querySelector(`.${this._opts.prefix}nav`);
        if (nav) nav.setAttribute('aria-label', opts.navAriaLabel);
      }
      if (opts.langSwitcherAriaLabel != null) {
        this._opts.langSwitcherAriaLabel = opts.langSwitcherAriaLabel;
        document.querySelectorAll(`.${this._opts.prefix}lang-switcher`).forEach(sw => {
          sw.setAttribute('aria-label', opts.langSwitcherAriaLabel);
        });
      }
    }

    /** @returns {string} DocShell version. */
    static get VERSION() { return VERSION; }
  }

  return DocShell;
});
