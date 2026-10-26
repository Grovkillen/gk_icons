// gk_icons: the icon library, the icon picker and the button Insert icon in the editor's toolbar. All read one list of
// every icon there is (core's, GK's and the packs'), fetched once per page when first needed.
//   the library (a page): look through all icons, search, choose a group, page through with core's page numbers, as a
//   grid or a list; a click copies how the icon is written and shows it in the panel beside: large, at four sizes,
//   its aspect ratio, how it is written, its pack and groups, its state, and icons with a similar name
//   the picker: any <input data-gk-icons-picker> becomes a button that shows the chosen icon and opens a small
//   window with a search field and the icons, as the field search in the filter builder does. The input keeps
//   the value (pack/name or a name), so the form works as before; without this script it is a plain text field.
//   the editor (the function icons.editor_insert): a button in core's wiki toolbar opens the same window and puts
//   the chosen icon's code at the caret, as Icons in text draws it.
// Plain DOM, no jQuery. The words come from the page (data-* on the element or window.GkIconsText).
(function () {
  var S = window.GkIcons;
  // the script can be on a page twice (the library asks for it, and so does the editor's function)
  if (!S || S.started) return;
  S.started = true;
  var T = window.GkIconsText || {};
  function t(k, d) { return T[k] || d; }
  // the marks core's page numbers and an image's size are written with (the file stays ASCII)
  var LAQUO = String.fromCharCode(171), RAQUO = String.fromCharCode(187), HELLIP = String.fromCharCode(8230), TIMES = String.fromCharCode(215);
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }
  function remember(k, v) {
    try {
      if (v === undefined) return window.localStorage.getItem('gk_icons.library.' + k);
      window.localStorage.setItem('gk_icons.library.' + k, v);
    } catch (e) { /* no memory in this browser: the defaults hold */ }
    return null;
  }

  var listPromise = {};
  // [{name, group, label}] : group is core, own or a pack's key. all: every icon with its state (an administrator's
  // list); the sprite chunk of each pack icon is noted in S.chunks so that S.svg draws it from the sprite
  function list(all) {
    var k = all ? 'all' : 'offered';
    if (!listPromise[k]) {
      listPromise[k] = fetch(S.namesUrl + (all ? (S.namesUrl.indexOf('?') >= 0 ? '&' : '?') + 'all=1' : ''), { credentials: 'same-origin', headers: { Accept: 'application/json' }, cache: all || changed ? 'no-store' : 'default' })
        .then(function (r) { return r.json(); })
        .then(function (d) {
          var out = [];
          S.chunks = S.chunks || {};
          (d.groups || []).forEach(function (g) {
            g.names.forEach(function (n, i) {
              var full = g.prefix + n;
              if (g.chunks) S.chunks[full] = g.chunks[i];
              out.push({ name: full, short: n, group: g.key, low: full.toLowerCase(), state: g.states ? g.states[i] : 'active' });
            });
          });
          out.groups = d.groups.map(function (g) { return { key: g.key, label: g.label, count: g.names.length, state: g.state || 'active' }; });
          // The instance's own groups across the packs; their key is set:<key> so it never meets a pack's
          out.sets = (d.sets || []).map(function (s) {
            var refs = {}; s.refs.forEach(function (r) { refs[r] = 1; });
            return { key: 'set:' + s.key, raw: s.key, label: s.label, refs: refs, count: s.refs.length, state: s.state || 'active', reason: s.reason || '' };
          });
          return out;
        });
    }
    return listPromise[k];
  }
  var changed = false; // after a change on this page the list is asked of the server, never the cache
  function forget() { listPromise = {}; changed = true; }
  function token() { var m = document.querySelector('meta[name="csrf-token"]'); return m ? m.content : ''; }
  function post(url, data) {
    var body = data instanceof URLSearchParams ? data : new URLSearchParams(data);
    return fetch(url, { method: 'POST', credentials: 'same-origin', body: body,
                        headers: { Accept: 'application/json', 'X-CSRF-Token': token() } })
      .then(function (r) { return r.json().then(function (j) { j.status = r.status; return j; }); });
  }
  function say(text) {
    if (window.GkGui && window.GkGui.whisper) { window.GkGui.whisper(text); return; }
    var n = document.getElementById('gk-icons-said') || document.body.appendChild(el('div', 'gk-icons-said'));
    n.id = 'gk-icons-said'; n.setAttribute('role', 'status'); n.textContent = text; n.classList.add('gk-icons-said-on');
    clearTimeout(say.timer); say.timer = setTimeout(function () { n.classList.remove('gk-icons-said-on'); }, 1600);
  }
  function copy(text, done) {
    function ok() { if (done) done(); }
    function old() {
      var a = el('textarea'); a.value = text; a.style.position = 'fixed'; a.style.insetBlockStart = '-1000px';
      document.body.appendChild(a); a.select();
      try { if (document.execCommand('copy')) ok(); } catch (e) { /* nothing copied, nothing said */ }
      a.remove();
    }
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(ok, old); else old();
  }
  // "Copied" for a moment at the element that was copied (it is positioned), read out as a status
  function notice(at) {
    var old0 = at.querySelector(':scope > .gk-icons-copied'); if (old0) old0.remove();
    var n = el('span', 'gk-icons-copied', t('copied', 'Copied')); n.setAttribute('role', 'status');
    at.appendChild(n);
    setTimeout(function () { n.remove(); }, 1400);
  }
  // how an icon is written in text: :fa/hammer:, and :gk/name: for core's and GK's own
  function own(i) { return i.group === 'core' || i.group === 'own'; }
  function inText(i) { return ':' + (own(i) ? 'gk/' + i.short : i.name) + ':'; }

  function cell(i, size) {
    var b = el('button', 'gk-icons-item'); b.type = 'button'; b.title = i.name;
    b.appendChild(S.svg(i.name, size || 24));
    b.appendChild(el('span', 'gk-icons-item-name', i.short));
    return b;
  }
  function setOf(sets, key) {
    var s = (sets || []).filter(function (x) { return x.key === key; });
    return s.length ? s[0] : null;
  }
  function stem(i) { var s = i.short.toLowerCase(); return s.replace(/(-[0-9a-f]{4,5})+$/, '') || s; }
  // sets: the groups across the packs (a filtered copy of the list has none of its own)
  function search(all, q, group, sets) {
    q = (q || '').trim().toLowerCase();
    var words = q.split(/\s+/).filter(Boolean);
    var set = group && group.indexOf('set:') === 0 ? setOf(sets || all.sets, group) : null;
    var hits = all.filter(function (i) {
      if (set) { if (!set.refs[i.name]) return false; } else if (group && i.group !== group) return false;
      for (var k = 0; k < words.length; k++) { if (i.low.indexOf(words[k]) < 0) return false; }
      return true;
    });
    if (!words.length) return hits;
    // exact name hits first: the whole name, then a name that is one of the words, then a name that starts
    // with the first word; within each the order given is kept (sort is stable)
    function rank(i) {
      // an emoji's name ends in its code (hammer-1f528, or several codes): the code is not part of the name here
      var s = stem(i);
      if (s === q || i.low === q) return 0;
      if (words.indexOf(s) >= 0) return 1;
      if (s.indexOf(words[0]) === 0) return 2;
      return 3;
    }
    return hits.map(function (i) { return [rank(i), i]; }).sort(function (x, y) { return x[0] - y[0]; }).map(function (x) { return x[1]; });
  }

  // ------------------------------------------------------------------ the library page
  // An administrator (data-gk-icons-admin) sees every icon of the active packs, the ones disabled one by one greyed with a
  // mark, filters them, checks many and acts on them in the box above the icons (the checkboxes show while that box is
  // open), and changes an icon's state in its panel; a disabled pack shows no icons and its chip is greyed. Everyone
  // looks, searches, copies and opens the panel.
  function library(root) {
    var admin = root.dataset.gkIconsAdmin === '1';
    function part(n) { return root.querySelector('[data-gk-icons="' + n + '"]'); }
    var input = part('search'), chips = part('groups'), grid = part('grid'), count = part('count'), pages = part('pages');
    var statesBox = part('states'), panel = part('panel'), main = part('main'), said = part('said'), selCount = part('selcount');
    var sortSel = part('sort'), viewSel = part('view'), selGroup = part('selgroup'), formSel = part('form');
    var tpl = root.querySelector('template[data-gk-icons="reason"]');
    var perOpts = (root.dataset.gkIconsPerPage || '25,50,100').split(',').map(Number).filter(function (n) { return n > 0; });
    var group = '', state = '', hits = [], all = [], timer = null, wired = false, selected = {}, packOn = {}, page = 1, openName = null, fid = 0;
    var per = Number(remember('per')); if (perOpts.indexOf(per) < 0) per = perOpts[0] || 25;
    if (viewSel && remember('view') === 'list') viewSel.value = 'list';
    if (sortSel && ['name_asc', 'name_desc', 'group'].indexOf(remember('sort')) >= 0) sortSel.value = remember('sort');
    if (formSel && ['text', 'name'].indexOf(remember('form')) >= 0) formSel.value = remember('form');
    if (formSel) formSel.addEventListener('change', function () { remember('form', formSel.value); });
    function form() { return formSel && formSel.value === 'name' ? 'name' : 'text'; }
    function tell(text) { if (said) { said.textContent = text; } else { say(text); } }
    function paintSel() {
      if (selCount) selCount.textContent = t('selected', '%{n} checked').replace('%{n}', Object.keys(selected).length);
    }
    // The checkboxes are for the box Checked icons: they show while it is open (without gui_stuff's box, always).
    // Folding the box unchecks every icon, so nothing stays checked out of sight.
    var wasMarking = null;
    function marking() {
      var box = root.querySelector('.gk-icons-sel-box fieldset');
      var on = !!box && !(box.classList.contains('collapsible') && box.classList.contains('collapsed'));
      root.classList.toggle('gk-icons-marking', admin && on);
      if (wasMarking === true && !on && Object.keys(selected).length) { selected = {}; draw(); paintSel(); }
      wasMarking = on;
    }
    if (admin) {
      var selBox = root.querySelector('.gk-icons-sel-box fieldset');
      if (selBox && window.MutationObserver) new MutationObserver(marking).observe(selBox, { attributes: true, attributeFilter: ['class'] });
      marking();
    }
    function sorted(list0) {
      var how = sortSel ? sortSel.value : 'name_asc';
      if (how === 'group') return list0; // the server's order: Redmine, GK's, then each pack, each by name
      var out = list0.slice().sort(function (a, b) { return a.short.localeCompare(b.short) || a.name.localeCompare(b.name); });
      return how === 'name_desc' ? out.reverse() : out;
    }
    function check(i, b) {
      var box = el('input', 'gk-icons-check'); box.type = 'checkbox'; box.checked = !!selected[i.name];
      box.title = t('mark_title', 'Check for the box Checked icons');
      box.setAttribute('aria-label', t('mark', 'Check') + ' ' + i.name);
      box.addEventListener('click', function (e) { e.stopPropagation(); });
      box.addEventListener('change', function () {
        if (box.checked) selected[i.name] = 1; else delete selected[i.name];
        if (b) b.classList.toggle('gk-icons-item-marked', box.checked);
        paintSel();
      });
      if (box.checked && b) b.classList.add('gk-icons-item-marked');
      return box;
    }
    function card(i) {
      var b = cell(i, 28), wrap = el('div', 'gk-icons-cell');
      wrap.dataset.gkIconsName = i.name;
      if (admin && i.state !== 'active') {
        b.classList.add('gk-icons-state-' + i.state);
        // not by colour alone: a mark with its words, for the eye and the screen reader
        b.title = i.name + ': ' + t('mark_' + i.state, t('state_' + i.state, i.state));
        b.appendChild(el('span', 'gk-icons-item-state', t('state_' + i.state, i.state)));
      }
      if (i.name === openName) { b.classList.add('gk-icons-item-open'); b.setAttribute('aria-pressed', 'true'); }
      if (admin) { var holder = el('span', 'gk-icons-check-holder'); holder.appendChild(check(i, b)); wrap.appendChild(holder); }
      wrap.appendChild(b);
      b.addEventListener('click', function () { choose(i, wrap); });
      return wrap;
    }
    function groupLabel(key) {
      var g = (all.groups || []).filter(function (x) { return x.key === key; })[0];
      return g ? g.label : key;
    }
    function badge(st) {
      var cls = { active: 'badge-status-closed', disabled: 'badge-status-locked' }[st] || 'badge-private';
      return el('span', 'badge ' + cls, t('state_' + st, st));
    }
    // the list view: core's list, one row per icon
    function table(slice) {
      var tb = el('table', 'list gk-icons-table'), head = el('tr'), body = el('tbody');
      if (admin) head.appendChild(el('th', 'checkbox'));
      [['icon', ''], ['name', t('name', 'Name')], ['group', t('pack', 'Pack')]].concat(admin ? [['status', t('state', 'State')]] : []).forEach(function (c) {
        head.appendChild(el('th', c[0], c[1]));
      });
      var th = el('thead'); th.appendChild(head); tb.appendChild(th); tb.appendChild(body);
      slice.forEach(function (i, n) {
        var tr = el('tr', (n % 2 ? 'even' : 'odd') + (i.name === openName ? ' context-menu-selection' : ''));
        tr.dataset.gkIconsName = i.name;
        if (admin) { var c0 = el('td', 'checkbox'); c0.appendChild(check(i, null)); tr.appendChild(c0); }
        var c1 = el('td', 'icon'); c1.appendChild(S.svg(i.name, 24)); tr.appendChild(c1);
        var c2 = el('td', 'name'), a = el('a', null, i.name); a.href = '#';
        a.addEventListener('click', function (e) { e.preventDefault(); choose(i, c2); });
        c2.style.position = 'relative'; c2.appendChild(a); tr.appendChild(c2);
        tr.appendChild(el('td', 'group', groupLabel(i.group)));
        if (admin) { var c4 = el('td', 'status'); c4.appendChild(badge(i.state)); tr.appendChild(c4); }
        body.appendChild(tr);
      });
      return tb;
    }
    function draw() {
      var last = Math.max(1, Math.ceil(hits.length / per));
      page = Math.min(Math.max(1, page), last);
      var from = (page - 1) * per, slice = hits.slice(from, from + per), view = viewSel ? viewSel.value : 'grid';
      grid.textContent = '';
      // no hits: core's no-data line across the box's full width, the same in both views (never a cell of the grid)
      grid.className = view === 'list' || !hits.length ? 'gk-icons-rows' : 'gk-icons-grid';
      if (!hits.length) grid.appendChild(el('p', 'nodata', t('no_match', 'No match')));
      else if (view === 'list') grid.appendChild(table(slice));
      else slice.forEach(function (i) { grid.appendChild(card(i)); });
      if (count) count.textContent = '(' + hits.length + ')';
      paginate(from, slice.length);
    }
    // core's page numbers, as pagination_links_full draws them: ul.pages with previous, the pages near this one, the
    // first and the last, next; then (first-last/count) and Per page
    function paginate(from, n) {
      pages.textContent = '';
      if (!hits.length) return;
      var last = Math.ceil(hits.length / per), ul = el('ul', 'pages');
      function li(cls, text, to) {
        var l = el('li', cls);
        if (to) {
          var a = el('a', null, text); a.href = '#';
          a.addEventListener('click', function (e) { e.preventDefault(); page = to; draw(); grid.scrollIntoView({ block: 'nearest' }); });
          l.appendChild(a);
        } else {
          l.appendChild(el('span', null, text));
        }
        ul.appendChild(l);
      }
      if (last > 1) li(page > 1 ? 'previous page' : 'previous', LAQUO + ' ' + t('previous', 'Previous'), page > 1 ? page - 1 : 0);
      var linked = [1, page, last];
      for (var p = page - 2; p <= page + 2; p++) { if (p > 1 && p < last) linked.push(p); }
      linked = linked.filter(function (x, k) { return linked.indexOf(x) === k; }).sort(function (x, y) { return x - y; });
      if (linked.length > 1) {
        var prev = null;
        linked.forEach(function (x) {
          if (prev && prev !== x - 1) li('spacer', HELLIP);
          if (x === page) li('current', String(x)); else li('page', String(x), x);
          prev = x;
        });
      }
      if (last > 1) li(page < last ? 'next page' : 'next', t('next', 'Next') + ' ' + RAQUO, page < last ? page + 1 : 0);
      pages.appendChild(ul);
      var info = el('span');
      info.appendChild(el('span', 'items', '(' + (from + 1) + '-' + (from + n) + '/' + hits.length + ')'));
      // core's per_page_options: the choices up to the first that holds every hit, and the one chosen
      var opts = perOpts, max;
      if (hits.length > opts[0]) { max = opts.filter(function (v) { return v >= hits.length; })[0] || hits.length; } else { max = hits.length; }
      opts = opts.filter(function (v) { return v <= max || v === per; });
      if (opts.length && !(opts.length === 1 && opts[0] === per)) {
        info.appendChild(document.createTextNode(' '));
        var pp = el('span', 'per-page'), words = t('per_page', 'Per page: %{value}').split('%{value}');
        pp.appendChild(document.createTextNode(words[0]));
        opts.forEach(function (v, k) {
          if (k) pp.appendChild(document.createTextNode(', '));
          if (v === per) { pp.appendChild(el('span', 'selected', String(v))); return; }
          var a = el('a', null, String(v)); a.href = '#';
          a.addEventListener('click', function (e) { e.preventDefault(); per = v; remember('per', String(v)); page = 1; draw(); });
          pp.appendChild(a);
        });
        pp.appendChild(document.createTextNode(words[1] || ''));
        info.appendChild(pp);
      }
      pages.appendChild(info);
    }
    function visible() {
      // a disabled pack lists no icons, not for an administrator either
      return all.filter(function (i) { return packOn[i.group] !== false; });
    }
    function run(keepPage) {
      hits = search(sorted(visible()), input.value, group, all.sets).filter(function (i) { return !state || i.state === state; });
      if (keepPage !== true) page = 1;
      draw();
    }
    function chip(label, n, on, pick) {
      var c = el('button', 'gk-icons-chip' + (on ? ' gk-icons-chip-on' : ''), label + (n != null ? ' (' + n + ')' : '')); c.type = 'button';
      c.setAttribute('aria-pressed', on ? 'true' : 'false');
      c.addEventListener('click', pick);
      return c;
    }
    function paintChips() {
      chips.textContent = '';
      chips.appendChild(chip(t('all', 'All'), visible().length, group === '', function () { group = ''; paintChips(); run(); }));
      (all.sets || []).forEach(function (s) {
        var label = s.label + (admin && s.state !== 'active' ? ' [' + t('state_' + s.state, s.state) + ']' : '');
        var c = chip(label, s.count, s.key === group, function () { group = s.key; paintChips(); run(); });
        c.classList.add('gk-icons-chip-set');
        chips.appendChild(c);
      });
      all.groups.forEach(function (g) {
        if (packOn[g.key] === false) {
          // the pack is disabled: its chip stays, greyed and not to be chosen, and says where it is switched on
          var off = chip(g.label + ' [' + t('state_' + g.state, g.state) + ']', null, false, function () {});
          off.disabled = true; off.classList.add('gk-icons-chip-off'); off.title = t('pack_off', 'The pack is disabled and shows no icons. It is enabled under the tab Packs.');
          off.setAttribute('aria-disabled', 'true');
          chips.appendChild(off);
          return;
        }
        chips.appendChild(chip(g.label, g.count, g.key === group, function () { group = g.key; paintChips(); run(); }));
      });
      if (!statesBox) return;
      statesBox.textContent = '';
      [['', t('all_states', 'All states')], ['disabled', t('only_disabled', 'Disabled')], ['missing', t('state_missing', 'missing on disk')]].forEach(function (p) {
        var n = visible().filter(function (i) { return !p[0] || i.state === p[0]; }).length;
        if (p[0] === 'missing' && !n) return;
        statesBox.appendChild(chip(p[1], n, state === p[0], function () { state = p[0]; paintChips(); run(); }));
      });
    }
    function load(keepPage) {
      return list(admin).then(function (a) {
        all = a; packOn = {};
        all.groups.forEach(function (g) { packOn[g.key] = g.state === 'active'; });
        if (group && group.indexOf('set:') !== 0 && packOn[group] === false) group = '';
        paintChips(); run(keepPage); paintSel();
        if (openName) {
          var again = all.filter(function (i) { return i.name === openName; })[0];
          if (again) openPanel(again); else shut();
        }
        if (!wired) {
          wired = true;
          input.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(run, 120); });
          if (sortSel) sortSel.addEventListener('change', function () { remember('sort', sortSel.value); run(); });
          if (viewSel) viewSel.addEventListener('change', function () { remember('view', viewSel.value); draw(); });
          input.focus();
        }
      });
    }
    // A click on an icon: copied as the choice above says, "Copied" at the icon, and the icon in the panel
    function choose(i, at) {
      var text = form() === 'name' ? i.name : inText(i);
      copy(text, function () { notice(at); });
      openPanel(i);
    }
    // The groups an icon is in, set at once (an icon of a pack, Redmine's or GK's alike)
    function groupBoxes(i) {
      var box = el('p', 'gk-icons-panel-groups');
      box.appendChild(el('strong', null, t('groups', 'Groups') + ': '));
      if (!(all.sets || []).length) { box.appendChild(el('em', 'info', t('no_groups', 'No groups yet'))); return box; }
      all.sets.forEach(function (s) {
        var l = el('label', 'inline'), c = el('input'); c.type = 'checkbox'; c.checked = !!s.refs[i.name];
        c.addEventListener('change', function () {
          c.disabled = true;
          post(root.dataset.gkIconsGroupsUrl + '/' + s.raw + '/members', { ref: i.name, member: c.checked ? '1' : '0' }).then(function (j) {
            c.disabled = false;
            if (!j.ok) { c.checked = !c.checked; tell(j.error || String(j.status)); return; }
            if (c.checked) { s.refs[i.name] = 1; s.count += 1; } else { delete s.refs[i.name]; s.count -= 1; }
            forget(); paintChips();
          });
        });
        l.appendChild(c); l.appendChild(document.createTextNode(' ' + s.label + ' ')); box.appendChild(l);
      });
      return box;
    }
    // The icon being looked at is marked in the grid or the list while its panel is open
    function markOpen() {
      grid.querySelectorAll('.gk-icons-item-open').forEach(function (x) { x.classList.remove('gk-icons-item-open'); x.removeAttribute('aria-pressed'); });
      grid.querySelectorAll('tr.context-menu-selection').forEach(function (x) { x.classList.remove('context-menu-selection'); });
      if (!openName) return;
      grid.querySelectorAll('[data-gk-icons-name]').forEach(function (x) {
        if (x.dataset.gkIconsName !== openName) return;
        if (x.tagName === 'TR') { x.classList.add('context-menu-selection'); return; }
        var b = x.querySelector('.gk-icons-item'); if (b) { b.classList.add('gk-icons-item-open'); b.setAttribute('aria-pressed', 'true'); }
      });
    }
    function shut() {
      openName = null;
      if (panel) { panel.hidden = true; panel.textContent = ''; }
      if (main) main.classList.remove('gk-icons-with-panel');
      markOpen();
    }
    // A field to read and copy, with core's copy icon beside it
    function field(label, value) {
      var p = el('p', 'gk-icons-field'), id = 'gk-icons-field-' + (++fid);
      var lb = el('label', null, label); lb.htmlFor = id;
      var inp = el('input'); inp.type = 'text'; inp.readOnly = true; inp.value = value; inp.id = id;
      inp.addEventListener('focus', function () { inp.select(); });
      var c = el('a', 'icon-only gk-icons-copy'); c.href = '#'; c.setAttribute('role', 'button');
      c.title = t('copy', 'Copy'); c.setAttribute('aria-label', t('copy', 'Copy') + ': ' + label);
      c.appendChild(S.svg('copy', 18));
      c.addEventListener('click', function (e) { e.preventDefault(); copy(value, function () { notice(p); }); });
      p.appendChild(lb); p.appendChild(inp); p.appendChild(document.createTextNode(' ')); p.appendChild(c);
      return p;
    }
    // width x height from the icon's own file: an svg's viewBox (or width and height), a png's size
    // The large picture by the icon's own aspect: a square stays 128 px, a wide or a tall one fills the preview box as
    // far as it goes on its long side (as object-fit: contain), so a 5:1 icon uses the box's width
    function fit(box, w, h) {
      var n = box.firstElementChild; if (!n) return;
      var maxW = Math.max(128, box.clientWidth - 16), maxH = Math.max(128, box.clientHeight - 16);
      var s = Math.min(maxW / w, maxH / h, 128 / Math.min(w, h));
      var bw = Math.round(w * s), bh = Math.round(h * s);
      if (n.tagName.toLowerCase() === 'svg') { n.setAttribute('width', bw); n.setAttribute('height', bh); }
      n.style.inlineSize = bw + 'px'; n.style.blockSize = bh + 'px';
    }
    function ratio(i, out, done) {
      fetch(S.url(i.name), { credentials: 'same-origin' }).then(function (r) {
        if (!r.ok) throw new Error(String(r.status));
        if ((r.headers.get('Content-Type') || '').indexOf('svg') >= 0) {
          return r.text().then(function (s) {
            var d = new DOMParser().parseFromString(s, 'image/svg+xml').documentElement;
            var vb = (d.getAttribute('viewBox') || '').trim().split(/[\s,]+/).map(Number);
            if (vb.length === 4) return [vb[2], vb[3]];
            return [parseFloat(d.getAttribute('width')), parseFloat(d.getAttribute('height'))];
          });
        }
        return r.blob().then(function (b) {
          return new Promise(function (resolve) {
            var img = new Image(), u = URL.createObjectURL(b);
            img.onload = function () { URL.revokeObjectURL(u); resolve([img.naturalWidth, img.naturalHeight]); };
            img.onerror = function () { URL.revokeObjectURL(u); resolve(null); };
            img.src = u;
          });
        });
      }).then(function (wh) {
        if (!wh || !(wh[0] > 0) || !(wh[1] > 0)) return;
        function num(x) { return String(Math.round(x * 100) / 100); }
        var w = wh[0], h = wh[1], r = (Math.round((w / h) * 100) / 100) + ':1';
        if (w === Math.round(w) && h === Math.round(h)) {
          var a = w, b = h; while (b) { var c = a % b; a = b; b = c; }
          if (w / a <= 32 && h / a <= 32) r = (w / a) + ':' + (h / a);
        }
        out.textContent = t('ratio', 'Aspect ratio') + ': ' + num(w) + ' ' + TIMES + ' ' + num(h) + ' (' + r + ')';
        if (done) done(w, h);
      }).catch(function () { /* no ratio shown */ });
    }
    // icons with the same first word in their name, the icon's own pack first
    function similar(i) {
      var s = stem(i).split(/[-_]/)[0];
      if (s.length < 2) return [];
      var same = visible().filter(function (j) { return j.name !== i.name && stem(j).split(/[-_]/)[0] === s; });
      same.sort(function (a, b) { return (a.group === i.group ? 0 : 1) - (b.group === i.group ? 0 : 1); });
      return same.slice(0, 8);
    }
    // The state form of a pack's icon: the state in a select, Save with Cancel as a link right beside it (core's
    // forms), and the shared reason field on its own line under them, never between them; nothing is saved before Save
    function stateForm(i, opener) {
      var f = el('form', 'gk-icons-state-form'); f.method = 'post'; f.action = root.dataset.gkIconsChooseUrl;
      var p = el('p'), sel = el('select'), b = el('input'); b.type = 'submit'; b.value = t('save', 'Save');
      sel.name = 'chosen'; sel.setAttribute('aria-label', t('state', 'State'));
      ['active', 'disabled'].forEach(function (c) {
        var o = el('option', null, t('choose_' + c, c)); o.value = c; sel.appendChild(o);
      });
      sel.value = i.state === 'disabled' ? 'disabled' : 'active';
      p.appendChild(sel); p.appendChild(document.createTextNode(' '));
      p.appendChild(b); p.appendChild(document.createTextNode(' '));
      var cancel = el('a', null, t('cancel', 'Cancel')); cancel.href = '#';
      cancel.addEventListener('click', function (e) { e.preventDefault(); f.remove(); opener.hidden = false; opener.focus(); });
      p.appendChild(cancel); f.appendChild(p);
      if (tpl) { var under = el('p', 'gk-icons-reason-under'); under.appendChild(tpl.content.cloneNode(true)); f.appendChild(under); }
      // Save sends the reason that is written (records' script takes it as Use the reason does); a required one left
      // empty stops the form (the browser, or records' script with the field's hint)
      f.addEventListener('submit', function (e) {
        if (e.defaultPrevented) return;
        e.preventDefault();
        var r = f.querySelector('[name="reason"]');
        if (sel.value === i.state) { tell(t('unchanged', 'The state is already that; nothing was saved.')); return; }
        b.disabled = true;
        post(root.dataset.gkIconsChooseUrl, { ref: i.name, chosen: sel.value, reason: r ? r.value : '', whole_pack: '0' }).then(function (j) {
          b.disabled = false;
          if (!j.ok) { tell(j.error || String(j.status)); return; }
          tell(t('saved', 'Saved') + ': ' + i.name);
          forget(); load(true);
        });
      });
      return f;
    }
    function openPanel(i) {
      if (!panel) return;
      openName = i.name; markOpen();
      if (main) main.classList.add('gk-icons-with-panel');
      panel.hidden = false; panel.textContent = '';
      var head = el('div', 'gk-icons-panel-head');
      head.appendChild(el('h3', null, i.name));
      if (admin) head.appendChild(badge(i.state));
      var x = el('a', 'icon-only gk-icons-panel-close'); x.href = '#'; x.setAttribute('role', 'button');
      x.title = t('close', 'Close'); x.setAttribute('aria-label', t('close', 'Close'));
      x.appendChild(S.svg('close', 18));
      x.addEventListener('click', function (e) { e.preventDefault(); shut(); input.focus(); });
      head.appendChild(x);
      panel.appendChild(head);
      // large, then at the sizes it is drawn at, then its aspect ratio
      var big = el('div', 'gk-icons-preview'); big.appendChild(S.svg(i.name, 128)); panel.appendChild(big);
      var sizes = el('div', 'gk-icons-sizes');
      [16, 24, 32, 48].forEach(function (n) {
        var fg = el('figure'); fg.appendChild(S.svg(i.name, n)); fg.appendChild(el('figcaption', null, n + ' px')); sizes.appendChild(fg);
      });
      panel.appendChild(sizes);
      var rt = el('p', 'gk-icons-ratio'); panel.appendChild(rt);
      ratio(i, rt, function (w, h) { if (openName === i.name) fit(big, w, h); });
      panel.appendChild(field(t('name', 'Name'), i.name));
      panel.appendChild(field(t('in_text', 'Used in text'), inText(i)));
      panel.appendChild(field(t('in_code', 'In a plugin'), "gk_icon('" + i.name + "')"));
      // the pack, and for a pack's icon the way to the whole pack's state
      var pk = el('p');
      pk.appendChild(el('strong', null, t('pack', 'Pack') + ': '));
      pk.appendChild(document.createTextNode(groupLabel(i.group) + ' '));
      if (admin && !own(i)) {
        var a = el('a', null, t('pack_change', 'The whole pack is changed under the tab Packs')); a.href = root.dataset.gkIconsPacksUrl + '#gk-icons-pack-' + i.group;
        pk.appendChild(a);
      }
      panel.appendChild(pk);
      if (admin) {
        panel.appendChild(groupBoxes(i));
        var stp = el('p');
        stp.appendChild(el('strong', null, t('state', 'State') + ': '));
        stp.appendChild(badge(i.state)); stp.appendChild(document.createTextNode(' '));
        panel.appendChild(stp);
        if (own(i)) {
          // Redmine's icons and GK's are used by Redmine and the plugins themselves: they have no state to change
          panel.appendChild(el('p', 'info', t('cannot_disable', "Redmine's icons and GK's icons cannot be disabled: Redmine and the plugins use them.")));
        } else {
          if (i.state === 'missing') panel.appendChild(el('p', 'info', t('missing_info', 'The file is no longer on disk.') + ' ' + t('missing_choose', '')));
          var open0 = el('a', null, t('change_state', 'Change the state...')); open0.href = '#';
          open0.addEventListener('click', function (e) {
            e.preventDefault(); open0.hidden = true;
            var f = stateForm(i, open0); stp.insertAdjacentElement('afterend', f);
            var s0 = f.querySelector('select[name="chosen"]'); if (s0) s0.focus();
          });
          stp.appendChild(open0);
        }
      } else {
        var mine = (all.sets || []).filter(function (s) { return s.refs[i.name]; }).map(function (s) { return s.label; });
        if (mine.length) { var gp = el('p'); gp.appendChild(el('strong', null, t('groups', 'Groups') + ': ')); gp.appendChild(document.createTextNode(mine.join(', '))); panel.appendChild(gp); }
      }
      var like = similar(i);
      if (like.length) {
        panel.appendChild(el('h4', null, t('similar', 'Similar icons')));
        var sg = el('div', 'gk-icons-similar');
        like.forEach(function (j) { var b = cell(j, 24); b.addEventListener('click', function () { openPanel(j); }); sg.appendChild(b); });
        panel.appendChild(sg);
      }
      panel.scrollIntoView({ block: 'nearest' });
    }
    if (panel) panel.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !e.target.matches('input[data-gk-reason]')) { shut(); input.focus(); } });
    // The box above the icons: the checked ones at once
    function many(url, data, done) {
      var refs = Object.keys(selected);
      if (!refs.length) { tell(t('none_marked', 'Check icons first')); return; }
      var body = new URLSearchParams();
      Object.keys(data).forEach(function (k) { body.append(k, data[k]); });
      refs.forEach(function (r) { body.append('refs[]', r); });
      post(url, body).then(function (j) {
        if (!j.ok) { tell(j.error || String(j.status)); return; }
        tell(t('changed', '%{n} changed').replace('%{n}', j.changed) + (j.skipped ? ', ' + t('skipped', '%{n} unchanged').replace('%{n}', j.skipped) : ''));
        if (done) done();
        forget(); load(true);
      });
    }
    // a reason field as new after it was used: the same field again, from the template
    function freshReason(f) {
      var r = f.querySelector('[name="reason"]'); if (!r || !tpl) return;
      (r.closest('.gk-records-reason-wrap') || r).replaceWith(tpl.content.cloneNode(true));
    }
    function wireBox() {
      function on(name, fn) { var b = part(name); if (b) b.addEventListener('click', function (e) { e.preventDefault(); fn(); }); }
      on('sel-all', function () { hits.forEach(function (i) { selected[i.name] = 1; }); draw(); paintSel(); });
      on('sel-none', function () { selected = {}; draw(); paintSel(); });
      var stateF = part('sel-state'), groupF = part('sel-group');
      if (stateF) {
        stateF.addEventListener('submit', function (e) {
          if (e.defaultPrevented) return;
          e.preventDefault();
          // the state chosen in the select is saved for every checked icon by Save
          var r = stateF.querySelector('[name="reason"]'), ch = stateF.querySelector('select[name="chosen"]');
          if (!ch || !ch.value) { if (ch) ch.focus(); return; }
          many(root.dataset.gkIconsChooseManyUrl, { chosen: ch.value, reason: r ? r.value : '' },
               function () { selected = {}; ch.value = ''; freshReason(stateF); });
        });
      }
      if (groupF) {
        groupF.addEventListener('submit', function (e) {
          e.preventDefault();
          if (!selGroup || !selGroup.value) { tell(t('choose_group', 'Choose a group')); if (selGroup) selGroup.focus(); return; }
          many(root.dataset.gkIconsGroupsUrl + '/' + selGroup.value + '/members_many', { member: e.submitter ? e.submitter.value : '1' });
        });
      }
    }
    if (admin) wireBox();
    var refreshF = part('refresh');
    if (refreshF) {
      refreshF.addEventListener('submit', function (e) {
        e.preventDefault();
        var btn = refreshF.querySelector('[type="submit"]');
        if (btn) btn.disabled = true;
        tell(t('refreshing', 'Reading the pack folders...'));
        post(refreshF.action, {}).then(function (j) {
          if (btn) btn.disabled = false;
          if (!j.ok) { tell(j.error || String(j.status)); return; }
          var c = j.counts || {};
          tell(t('refreshed', 'Read: %{added} new, %{changed} changed, %{missing} missing on disk, %{unchanged} unchanged')
            .replace('%{added}', c.added || 0).replace('%{changed}', c.changed || 0)
            .replace('%{missing}', c.missing || 0).replace('%{unchanged}', c.unchanged || 0));
          forget(); load(true);
        });
      });
    }
    load();
  }

  // ------------------------------------------------------------------ the Packs tab: height, place and space in text
  // A row's link opens the window (core's modal) with the values in use and the pack's first icon in three sizes of
  // text; the icons follow the fields while they are changed, and Save keeps them. A cleared field shows the pack's own
  // value (its placeholder), which is also what the server keeps for it.
  var FIT = ['scale', 'shift', 'gap'];
  function fitPaint(form) {
    var v = {};
    FIT.forEach(function (k) { var f = form.querySelector('[data-gk-icons-fit="' + k + '"]'); v[k] = f.value !== '' ? f.value : f.placeholder; });
    form.querySelectorAll('[data-gk-icons-fit-slot] svg, [data-gk-icons-fit-slot] span.gk-icon').forEach(function (i) {
      i.style.setProperty('--gk-scale', v.scale); i.style.setProperty('--gk-shift', v.shift + 'em'); i.style.setProperty('--gk-gap', v.gap + 'em');
    });
  }
  // A value off the field's step (a pack.yml can give 1.12) would stop the form in the browser: the field then takes any
  // value, and the arrows step from the value shown
  function fitStep(f, value) {
    var step = parseFloat(f.getAttribute('data-gk-icons-step') || f.getAttribute('step'));
    if (!f.hasAttribute('data-gk-icons-step')) f.setAttribute('data-gk-icons-step', String(step));
    var min = parseFloat(f.getAttribute('min')) || 0, n = (parseFloat(value) - min) / step;
    f.setAttribute('step', value === '' || Math.abs(n - Math.round(n)) < 1e-6 ? String(step) : 'any');
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('[data-gk-icons-fit-open]');
    var box = document.getElementById('gk-icons-fit-modal');
    if (!a || !box || typeof window.showModal !== 'function') return;
    e.preventDefault();
    var d = a.dataset, form = box.querySelector('form');
    form.action = d.url;
    FIT.forEach(function (k) {
      var f = form.querySelector('[data-gk-icons-fit="' + k + '"]'), K = k.charAt(0).toUpperCase() + k.slice(1);
      f.value = d[k] != null ? d[k] : ''; f.placeholder = d['ph' + K] != null ? d['ph' + K] : '';
      fitStep(f, f.value);
    });
    var tpl = document.querySelector('template[data-gk-icons-fit-sample="' + d.gkIconsFitOpen + '"]');
    box.querySelectorAll('[data-gk-icons-fit-slot]').forEach(function (slot) {
      slot.textContent = '';
      if (tpl) slot.appendChild(tpl.content.cloneNode(true));
    });
    fitPaint(form);
    window.showModal('gk-icons-fit-modal', '560px', box.querySelector('h3.title').textContent + ': ' + d.name);
    // the dialog opened at the page's corner from here (top and left 0); placed in the window's middle as core's are
    if (window.jQuery) window.jQuery(box).dialog('option', 'position', { my: 'center', at: 'center', of: window });
  });
  document.addEventListener('input', function (e) {
    var f = e.target.closest && e.target.closest('[data-gk-icons-fit]');
    if (f && f.form) fitPaint(f.form);
  });

  // ------------------------------------------------------------------ the picker's window (the picker and the editor)
  var pop = null;
  function close() { if (pop) { pop.el.remove(); pop.anchor.setAttribute('aria-expanded', 'false'); pop = null; } }
  // done(icon or null); opts: current (the chosen name, marked), none (offer No icon), back (where the focus goes after)
  function open(anchor, done, opts) {
    close();
    opts = opts || {};
    var back = opts.back || anchor;
    var p = el('div', 'gk-icons-pop');
    var q = el('input'); q.type = 'search'; q.placeholder = t('search', 'Search icon'); q.setAttribute('aria-label', t('search', 'Search icon'));
    // the packs and groups in one list, not a chip each: with many packs the chips took the window's height
    var groups = el('select', 'gk-icons-pop-groups'); groups.setAttribute('aria-label', t('pack_or_group', 'Pack or group'));
    var ul = el('div', 'gk-icons-pop-grid'); ul.setAttribute('role', 'listbox');
    var foot = el('div', 'gk-icons-pop-foot');
    var info = el('span', 'gk-icons-pop-info');
    function pick(i) { close(); done(i); back.focus(); }
    if (opts.none) {
      var none = el('button', 'gk-icons-pop-none', t('none', 'No icon')); none.type = 'button';
      none.addEventListener('click', function () { pick(null); });
      foot.appendChild(none);
    }
    foot.appendChild(info);
    p.appendChild(q); p.appendChild(groups); p.appendChild(ul); p.appendChild(foot);
    document.body.appendChild(p);
    // below the anchor; above it when there is not room below and more room above; never taller than the window
    function place() {
      var r = anchor.getBoundingClientRect(), vh = document.documentElement.clientHeight, h = p.offsetHeight;
      var below = vh - r.bottom - 8, above = r.top - 8;
      var top = (h > below && above > below) ? Math.max(8, r.top - 4 - h) : r.bottom + 4;
      p.style.insetBlockStart = (window.scrollY + top) + 'px';
      p.style.insetInlineStart = Math.max(8, Math.min(window.scrollX + r.left, window.scrollX + document.documentElement.clientWidth - p.offsetWidth - 8)) + 'px';
    }
    place();
    anchor.setAttribute('aria-expanded', 'true');
    pop = { el: p, anchor: anchor };
    // Escape closes wherever the focus is in the window
    p.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.preventDefault(); close(); back.focus(); } });
    list().then(function (all) {
      if (!pop || pop.el !== p) return;
      var group = '', hit = 0, shown = [];
      function draw() {
        var m = search(all, q.value, group);
        shown = m.slice(0, 160);
        hit = Math.min(hit, Math.max(0, shown.length - 1));
        ul.textContent = '';
        if (!shown.length) ul.appendChild(el('div', 'gk-icons-pop-empty', t('no_match', 'No match')));
        shown.forEach(function (i, n) {
          var b = cell(i, 22);
          b.setAttribute('role', 'option');
          if (n === hit) b.classList.add('gk-icons-hit');
          if (i.name === opts.current) b.classList.add('gk-icons-chosen');
          b.addEventListener('mousedown', function (e) { e.preventDefault(); pick(i); });
          ul.appendChild(b);
        });
        info.textContent = m.length > shown.length ? t('showing', 'showing %{shown} of %{count}').replace('%{shown}', shown.length).replace('%{count}', m.length) : '';
        var cur = ul.querySelector('.gk-icons-hit'); if (cur && cur.scrollIntoView) cur.scrollIntoView({ block: 'nearest' });
      }
      function option(parent, key, label) { var o = el('option', null, label); o.value = key; parent.appendChild(o); }
      option(groups, '', t('all', 'All'));
      if ((all.sets || []).length) {
        var sets = el('optgroup'); sets.label = t('groups', 'Groups');
        all.sets.forEach(function (s) { option(sets, s.key, s.label); });
        groups.appendChild(sets);
      }
      if (all.groups.length) {
        var packs = el('optgroup'); packs.label = t('pack', 'Pack');
        all.groups.forEach(function (g) { option(packs, g.key, g.label); });
        groups.appendChild(packs);
      }
      groups.addEventListener('change', function () { group = groups.value; hit = 0; draw(); q.focus(); });
      q.addEventListener('input', function () { hit = 0; draw(); });
      q.addEventListener('keydown', function (e) {
        var cols = Math.max(1, Math.floor(ul.clientWidth / 96));
        if (e.key === 'ArrowRight') { hit = Math.min(hit + 1, shown.length - 1); draw(); e.preventDefault(); }
        else if (e.key === 'ArrowLeft') { hit = Math.max(hit - 1, 0); draw(); e.preventDefault(); }
        else if (e.key === 'ArrowDown') { hit = Math.min(hit + cols, shown.length - 1); draw(); e.preventDefault(); }
        else if (e.key === 'ArrowUp') { hit = Math.max(hit - cols, 0); draw(); e.preventDefault(); }
        else if (e.key === 'Enter') { e.preventDefault(); if (shown[hit]) pick(shown[hit]); }
      });
      draw();
      place();
    });
    q.focus();
  }
  function picker(input) {
    if (input.dataset.gkIconsPickerOn) return;
    input.dataset.gkIconsPickerOn = '1';
    var b = el('button', 'gk-icons-pick'); b.type = 'button';
    b.setAttribute('aria-haspopup', 'listbox'); b.setAttribute('aria-expanded', 'false');
    if (input.getAttribute('aria-label')) b.setAttribute('aria-label', input.getAttribute('aria-label'));
    function paint() {
      b.textContent = '';
      if (input.value) { b.appendChild(S.svg(input.value, 18)); b.appendChild(el('span', 'gk-icons-pick-name', input.value)); }
      else { b.appendChild(el('span', 'gk-icons-pick-none', t('none', 'No icon'))); }
      b.appendChild(el('span', 'gk-icons-pick-caret', ''));
    }
    function chosen(i) {
      input.value = i ? i.name : '';
      input.dispatchEvent(new Event('input', { bubbles: true })); input.dispatchEvent(new Event('change', { bubbles: true }));
      paint();
    }
    b.addEventListener('click', function () { if (pop && pop.anchor === b) close(); else open(b, chosen, { current: input.value, none: true }); });
    input.type = 'hidden';
    input.insertAdjacentElement('afterend', b);
    paint();
  }
  // A press outside the window closes it. The event's path is read, not the target's place now: a group chip draws the
  // chips anew on its own mousedown, so by the time the press reaches the document its target is no longer in the window.
  document.addEventListener('mousedown', function (e) {
    if (!pop) return;
    var path = e.composedPath ? e.composedPath() : [];
    if (path.indexOf(pop.el) >= 0 || path.indexOf(pop.anchor) >= 0) return;
    if (pop.el.contains(e.target) || pop.anchor.contains(e.target)) return;
    close();
  });

  // ------------------------------------------------------------------ the editor's toolbar (icons.editor_insert)
  // A tool in core's jsToolBar (the same in Redmine 6.0 to 7.0, textile and common_mark): jsToolBar.prototype.elements,
  // drawn by each toolbar's draw(). It stands before core's Help, as core's own tools do. A toolbar drawn before this
  // script ran gets the same button put in its row, as core's jsButton draws one.
  var TOOL = 'gk_icons_insert';
  function insertAt(ta, text) {
    var s = ta.selectionStart, e = ta.selectionEnd;
    ta.focus();
    if (typeof ta.setRangeText === 'function') ta.setRangeText(text, s, e, 'end');
    else { ta.value = ta.value.slice(0, s) + text + ta.value.slice(e); ta.setSelectionRange(s + text.length, s + text.length); }
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  }
  function openFor(anchor, ta) {
    if (!anchor || !ta) return;
    if (pop && pop.anchor === anchor) { close(); return; }
    open(anchor, function (i) { if (i) insertAt(ta, inText(i)); }, { back: ta });
  }
  function editor() {
    var J = window.jsToolBar;
    if (!S.editorInsert || !J || !J.prototype || !J.prototype.elements) return;
    var label = t('insert', 'Insert icon'), icon = S.url('swatch'), els = J.prototype.elements;
    if (!els[TOOL]) {
      // core's Help and the space before it move after the new tool; the rest keeps its order
      var keys = Object.keys(els), at = keys.indexOf('help');
      if (at > 0 && els[keys[at - 1]] && els[keys[at - 1]].type === 'space') at -= 1;
      var tail = at >= 0 ? keys.slice(at) : [], kept = {};
      tail.forEach(function (k) { kept[k] = els[k]; delete els[k]; });
      els[TOOL] = { type: 'button', title: label, icon: icon,
                    fn: { wiki: function () { openFor(this.toolNodes[TOOL], this.textarea); } } };
      tail.forEach(function (k) { els[k] = kept[k]; });
    }
    document.querySelectorAll('.jstElements').forEach(function (bar) {
      if (bar.querySelector('.jstb_' + TOOL)) return;
      var block = bar.closest('.jstBlock'), ta = block && block.querySelector('.jstEditor textarea');
      if (!ta) return;
      var b = document.createElement('button'); b.type = 'button'; b.tabIndex = 200; b.className = 'jstb_' + TOOL; b.title = label;
      b.appendChild(el('span', null, label));
      b.style.backgroundImage = 'url(' + icon + ')';
      b.onclick = function () { openFor(b, ta); return false; };
      var help = bar.querySelector('.jstb_help'), before = help;
      if (help && help.previousElementSibling && help.previousElementSibling.classList.contains('jstSpacer')) before = help.previousElementSibling;
      bar.insertBefore(b, before || null);
    });
  }

  S.picker = picker;
  S.library = library;
  function start() {
    document.querySelectorAll('input[data-gk-icons-picker]').forEach(picker);
    var lib = document.querySelector('[data-gk-icons-library]'); if (lib) library(lib);
    editor();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
