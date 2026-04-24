/*!
 * DocShellSearch v1.0.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Full-text search module for DocShell.
 * Indexes all parsed pages and provides a keyboard-navigable search UI
 * that can be mounted into DocShell's built-in search slot or any element.
 *
 * Requires: DocShell (doc-shell.js)
 *
 * Author : DocShell contributors
 * License: MIT
 */

(function (global, factory) {
  if (typeof module === 'object' && typeof module.exports === 'object') {
    module.exports = factory();
  } else {
    global.DocShellSearch = factory();
  }
})(typeof window !== 'undefined' ? window : globalThis, function () {
  'use strict';

  // ─── Utilities ───────────────────────────────────────────────────────────────

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
      .replace(/"/g, '&quot;');
  }

  /** Escape special RegExp characters in a string */
  function escRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  // ─── DocShellSearch ──────────────────────────────────────────────────────────

  class DocShellSearch {
    /**
     * @param {object} docShell    - A DocShell instance.
     * @param {object} [options]
     * @param {number}   [options.minLength]      - Minimum query length. Default: 2
     * @param {number}   [options.maxResults]     - Maximum results shown. Default: 30
     * @param {number}   [options.snippetPad]     - Characters before match in snippet. Default: 40
     * @param {number}   [options.snippetLen]     - Characters after match in snippet. Default: 120
     * @param {string}   [options.placeholder]    - Input placeholder. Default: 'Search…'
     * @param {string}   [options.noResultsText]  - No-results message. Default: 'No results found.'
     * @param {string}   [options.prefix]         - CSS class prefix (inherits from DocShell). Default: 'ds-'
     * @param {function} [options.onNavigate]     - Callback fired when a result is selected: fn(slug)
     */
    constructor(docShell, options = {}) {
      if (!docShell) throw new Error('[DocShellSearch] A DocShell instance is required as the first argument.');

      this._ds   = docShell;
      this._opts = {
        minLength:     options.minLength     ?? 2,
        maxResults:    options.maxResults    ?? 30,
        snippetPad:    options.snippetPad    ?? 40,
        snippetLen:    options.snippetLen    ?? 120,
        placeholder:   options.placeholder   ?? 'Search…',
        noResultsText: options.noResultsText ?? 'No results found.',
        searchAriaLabel: options.searchAriaLabel ?? 'Search documentation',
        /** @type {Record<string, string>|null} Map result type keys (h1…h6, text, code, table) to display labels */
        typeLabels:    options.typeLabels    ?? null,
        prefix:        options.prefix        ?? (docShell._opts?.prefix || 'ds-'),
        onNavigate:    options.onNavigate    ?? null,
      };

      /** @type {Array<IndexEntry>} */
      this._index      = [];
      this._inputEl    = null;
      this._dropdownEl = null;
      this._wrapperEl  = null;
      this._docClickHandler = null;

      // Automatically rebuild the index whenever DocShell loads new content
      this._ds.on('ready', () => this.buildIndex());
    }

    /**
     * @param {object} strings
     * @param {string} [strings.placeholder]
     * @param {string} [strings.noResultsText]
     * @param {string} [strings.searchAriaLabel]
     * @param {Record<string, string>|null} [strings.typeLabels]
     */
    setStrings(strings = {}) {
      if (strings.placeholder != null) {
        this._opts.placeholder = strings.placeholder;
        if (this._inputEl) this._inputEl.placeholder = strings.placeholder;
      }
      if (strings.noResultsText != null) {
        this._opts.noResultsText = strings.noResultsText;
      }
      if (strings.searchAriaLabel != null) {
        this._opts.searchAriaLabel = strings.searchAriaLabel;
        if (this._inputEl) this._inputEl.setAttribute('aria-label', strings.searchAriaLabel);
      }
      if (strings.typeLabels !== undefined) {
        this._opts.typeLabels = strings.typeLabels;
      }
    }

    _formatTypeLabel(type) {
      const map = this._opts.typeLabels;
      if (map && typeof map[type] === 'string') return map[type];
      return type;
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Indexing
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * Build (or rebuild) the full-text search index from all DocShell pages.
     * This is called automatically on 'ready' events, but you can call it
     * manually if you modify pages programmatically.
     * @returns {DocShellSearch}
     */
    buildIndex() {
      this._index = [];
      for (const page of this._ds.getPages()) {
        this._indexPage(page);
      }
      return this;
    }

    /**
     * @typedef {object} IndexEntry
     * @property {string} slug       - Page slug
     * @property {string} pageTitle  - Page title
     * @property {string} section    - Nearest heading above this entry
     * @property {string} type       - 'h1'–'h6', 'text', 'table', 'code'
     * @property {string} text       - Searchable plain text
     */

    _indexPage(page) {
      const lines          = page.md.split('\n');
      let   currentSection = page.title;
      let   buffer         = [];
      let   inCode         = false;
      let   inTable        = false;

      const flush = (type = 'text') => {
        const text = buffer.join(' ').trim();
        if (text.length > 5) {
          this._index.push({
            slug:      page.slug,
            pageTitle: page.title,
            section:   currentSection,
            type,
            text,
          });
        }
        buffer = [];
      };

      for (const rawLine of lines) {
        const line = rawLine.trim();

        // ── Fenced code blocks ──────────────────────────────────────────────
        if (line.startsWith('```')) {
          if (!inCode) {
            // Start of a code block — flush buffered text first
            flush();
            inCode = true;
          } else {
            inCode = false;
          }
          continue;
        }
        if (inCode) {
          // Index code content under a 'code' type
          if (line.length > 3) buffer.push(line);
          if (buffer.length >= 5) flush('code');
          continue;
        }

        // ── Skip HTML comments and blank lines ──────────────────────────────
        if (!line || line.startsWith('<!--')) {
          flush();
          continue;
        }

        // ── Headings ────────────────────────────────────────────────────────
        const hMatch = line.match(/^(#{1,6})\s+(.+)$/);
        if (hMatch) {
          flush();
          const level         = hMatch[1].length;
          const headingText   = hMatch[2].replace(/[*_`[\]]/g, '').trim();
          currentSection      = headingText;
          this._index.push({
            slug:      page.slug,
            pageTitle: page.title,
            section:   headingText,
            type:      `h${level}`,
            text:      headingText,
          });
          inTable = false;
          continue;
        }

        // ── Tables ──────────────────────────────────────────────────────────
        if (line.startsWith('|')) {
          // Skip separator rows (---|---|---)
          if (/^\|[\s|:-]+\|$/.test(line)) continue;
          inTable = true;
          const cells = line
            .split('|')
            .map(c => c.trim().replace(/[*_`]/g, ''))
            .filter(c => c.length > 0);
          cells.forEach(cell => {
            if (cell.length > 3) {
              this._index.push({
                slug:      page.slug,
                pageTitle: page.title,
                section:   currentSection,
                type:      'table',
                text:      cell,
              });
            }
          });
          continue;
        }

        inTable = false;

        // ── Horizontal rules ────────────────────────────────────────────────
        if (/^[-*]{3,}$/.test(line)) { flush(); continue; }

        // ── Regular text (paragraphs, lists, blockquotes) ───────────────────
        const clean = line
          .replace(/!\[.*?\]\(.*?\)/g, '')          // images
          .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')  // links → text
          .replace(/[*_`~]/g, '')                    // inline formatting
          .replace(/^[-*+]\s+/, '')                  // unordered list markers
          .replace(/^\d+\.\s+/, '')                  // ordered list markers
          .replace(/^>\s+/, '')                      // blockquote markers
          .replace(/^[-:]+$/, '')                    // table separators
          .trim();

        if (clean.length > 5) buffer.push(clean);

        // Flush after accumulating a few lines to keep entries focused
        if (buffer.length >= 4) flush();
      }

      flush(); // flush any remaining buffer
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Search
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * Search the index for a query string.
     * @param {string} query
     * @returns {Array<SearchResult>}
     */
    search(query) {
      query = String(query).trim();
      if (!query || query.length < this._opts.minLength) return [];

      const qLow    = query.toLowerCase();
      const results = [];
      const seen    = new Set();

      for (const entry of this._index) {
        if (!entry.text.toLowerCase().includes(qLow)) continue;

        // Deduplicate by (slug + section) for non-heading entries
        const key = `${entry.slug}::${entry.section}`;
        if (entry.type === 'text' && seen.has(key)) continue;
        seen.add(key);

        // Build a snippet centred around the match
        const textLow = entry.text.toLowerCase();
        const matchIdx = textLow.indexOf(qLow);
        const start    = Math.max(0, matchIdx - this._opts.snippetPad);
        const end      = Math.min(entry.text.length, matchIdx + qLow.length + this._opts.snippetLen);
        const snippet  =
          (start > 0 ? '…' : '') +
          entry.text.slice(start, end) +
          (end < entry.text.length ? '…' : '');

        // Score: headings rank higher, h1 > h2 > ... > text
        const typeScore =
          entry.type === 'h1' ? 8 :
          entry.type === 'h2' ? 7 :
          entry.type === 'h3' ? 6 :
          entry.type === 'h4' ? 5 :
          entry.type === 'h5' ? 4 :
          entry.type === 'h6' ? 3 :
          entry.type === 'table' ? 2 : 1;

        // Bonus if match is in the page title
        const titleBonus = entry.pageTitle.toLowerCase().includes(qLow) ? 3 : 0;

        results.push({
          slug:      entry.slug,
          pageTitle: entry.pageTitle,
          section:   entry.section,
          type:      entry.type,
          snippet,
          score:     typeScore + titleBonus,
        });

        if (results.length >= this._opts.maxResults * 3) break; // gather extras for better sorting
      }

      return results
        .sort((a, b) => b.score - a.score)
        .slice(0, this._opts.maxResults);
    }

    /**
     * Return snippet HTML with the query terms wrapped in
     * <mark class="ds-search-mark">…</mark> for highlighting.
     * @param {string} text
     * @param {string} query
     * @returns {string} HTML string
     */
    highlightSnippet(text, query) {
      const p  = this._opts.prefix;
      const re = new RegExp(`(${escRe(query)})`, 'gi');
      return escHtml(text).replace(re, `<mark class="${p}search-mark">$1</mark>`);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  UI — mount a ready-made search widget
    // ════════════════════════════════════════════════════════════════════════════

    /**
     * Mount the search input + dropdown into a container.
     * Typically called with `ds.getSearchSlot()` as the argument.
     *
     * @param {string|Element} slot - CSS selector or DOM element.
     * @returns {DocShellSearch}
     */
    mount(slot) {
      const p  = this._opts.prefix;
      const el = (typeof slot === 'string') ? document.querySelector(slot) : slot;
      if (!el) throw new Error(`[DocShellSearch] Mount slot not found: "${slot}"`);

      el.innerHTML =
        `<div class="${p}search-wrapper" role="search">` +
          `<input ` +
            `class="${p}search-input" ` +
            `type="search" ` +
            `placeholder="${escAttr(this._opts.placeholder)}" ` +
            `autocomplete="off" ` +
            `aria-label="${escAttr(this._opts.searchAriaLabel)}" ` +
            `aria-autocomplete="list" ` +
            `aria-expanded="false" ` +
            `aria-haspopup="listbox"` +
          `>` +
          `<div class="${p}search-dropdown" role="listbox" hidden></div>` +
        `</div>`;

      this._wrapperEl  = el.querySelector(`.${p}search-wrapper`);
      this._inputEl    = el.querySelector(`.${p}search-input`);
      this._dropdownEl = el.querySelector(`.${p}search-dropdown`);

      this._inputEl.addEventListener('input',   ()  => this._handleInput());
      this._inputEl.addEventListener('keydown', (e) => this._handleKeydown(e));
      this._inputEl.addEventListener('focus',   ()  => {
        // Re-show last results on re-focus if there's still a query
        if (this._inputEl.value.trim().length >= this._opts.minLength) this._handleInput();
      });
      if (!this._docClickHandler) {
        this._docClickHandler = (e) => {
          if (!this._wrapperEl?.contains(e.target)) this._closeDropdown();
        };
        document.addEventListener('click', this._docClickHandler);
      }

      // Build index if it hasn't been built yet
      if (this._index.length === 0) this.buildIndex();
      return this;
    }

    // ─── UI event handlers ───────────────────────────────────────────────────

    _handleInput() {
      const q = this._inputEl.value.trim();
      if (q.length < this._opts.minLength) { this._closeDropdown(); return; }
      const results = this.search(q);
      this._renderDropdown(results, q);
    }

    _renderDropdown(results, query) {
      const p  = this._opts.prefix;
      const dd = this._dropdownEl;

      if (!results.length) {
        dd.innerHTML =
          `<div class="${p}search-no-results">${escHtml(this._opts.noResultsText)}</div>`;
        dd.removeAttribute('hidden');
        this._inputEl.setAttribute('aria-expanded', 'true');
        return;
      }

      const items = results.map((r, i) => {
        const isHeading  = r.type.startsWith('h');
        const typeClass  = `${p}search-item--${r.type}`;
        const pageLabel  = escHtml(r.pageTitle);
        const sectionHTML = r.section !== r.pageTitle
          ? `<span class="${p}search-item-section">${escHtml(r.section)}</span>`
          : '';

        return (
          `<div ` +
            `class="${p}search-item ${typeClass}" ` +
            `role="option" ` +
            `data-slug="${escAttr(r.slug)}" ` +
            `data-index="${i}" ` +
            `tabindex="-1"` +
          `>` +
            `<div class="${p}search-item-meta">` +
              `<span class="${p}search-item-page">${pageLabel}</span>` +
              sectionHTML +
              `<span class="${p}search-item-type">${escHtml(this._formatTypeLabel(r.type))}</span>` +
            `</div>` +
            `<div class="${p}search-item-snippet">` +
              this.highlightSnippet(r.snippet, query) +
            `</div>` +
          `</div>`
        );
      }).join('');

      dd.innerHTML = items;
      dd.removeAttribute('hidden');
      this._inputEl.setAttribute('aria-expanded', 'true');

      // Attach click handlers
      dd.querySelectorAll(`.${p}search-item`).forEach(item => {
        item.addEventListener('mousedown', e => {
          e.preventDefault(); // prevent input blur before click fires
          this._selectItem(item.dataset.slug);
        });
      });
    }

    _handleKeydown(e) {
      const p     = this._opts.prefix;
      const items = [...(this._dropdownEl?.querySelectorAll(`.${p}search-item`) ?? [])];
      if (!items.length && e.key !== 'Escape') return;

      const focused = this._dropdownEl?.querySelector(`.${p}search-item--focused`);
      let   idx     = focused ? items.indexOf(focused) : -1;

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          idx = Math.min(idx + 1, items.length - 1);
          break;
        case 'ArrowUp':
          e.preventDefault();
          idx = Math.max(idx - 1, 0);
          break;
        case 'Enter':
          e.preventDefault();
          if (focused) { this._selectItem(focused.dataset.slug); return; }
          // If no item focused, navigate to first result
          if (items[0]) { this._selectItem(items[0].dataset.slug); return; }
          return;
        case 'Escape':
          this._closeDropdown();
          this._inputEl.blur();
          return;
        case 'Tab':
          this._closeDropdown();
          return;
        default:
          return;
      }

      // Update focus indicator
      items.forEach(it => it.classList.remove(`${p}search-item--focused`));
      if (items[idx]) {
        items[idx].classList.add(`${p}search-item--focused`);
        items[idx].scrollIntoView({ block: 'nearest' });
        this._inputEl.setAttribute('aria-activedescendant', `${p}search-item-${idx}`);
      }
    }

    _selectItem(slug) {
      this._ds.navigate(slug);
      this._inputEl.value = '';
      this._closeDropdown();
      if (this._opts.onNavigate) this._opts.onNavigate(slug);
    }

    _closeDropdown() {
      if (this._dropdownEl) {
        this._dropdownEl.setAttribute('hidden', '');
        this._dropdownEl.innerHTML = '';
      }
      if (this._inputEl) {
        this._inputEl.setAttribute('aria-expanded', 'false');
        this._inputEl.removeAttribute('aria-activedescendant');
      }
    }

    /** Cierra el panel de resultados (p. ej. tras redimensionar o mover el slot al sidebar). */
    closeDropdown() {
      this._closeDropdown();
    }

    // ════════════════════════════════════════════════════════════════════════════
    //  Public helpers
    // ════════════════════════════════════════════════════════════════════════════

    /** @returns {number} Total number of indexed entries. */
    getIndexSize() { return this._index.length; }

    /** @returns {Array<IndexEntry>} Cloned copy of the full index. */
    getIndex() { return [...this._index]; }
  }

  return DocShellSearch;
});
