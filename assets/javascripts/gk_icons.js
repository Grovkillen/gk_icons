// gk_icons: the icon library, the icon picker and the button Insert icon in the editor's toolbar. All read one list of
// every icon there is (core's, GK's and the packs'), fetched once per page when first needed.
//   the library (a page, on GK GUI Stuff's library as data): look through all icons, search, choose a pack or a
//   group, page through with core's page numbers, as a grid or core's list; a click copies how the icon is written
//   and shows it in the panel beside: large, at four sizes, its aspect ratio, how it is written, its pack and groups,
//   its state, and icons with a similar name
//   the picker: any <input data-gk-icons-picker> becomes a button that shows the chosen icon and opens GK GUI Stuff's
//   surface in the upper layer (GkGui.layer) with a search field and the icons, as the field search in the filter
//   builder does. The input keeps the value (pack/name or a name), so the form works as before; without this script
//   it is a plain text field.
//   the editor (the function icons.editor_insert): a button in core's wiki toolbar opens the same surface and puts
//   the chosen icon's code at the caret, as Icons in text draws it.
// GK GUI Stuff is required (the plugin does nothing without it), so its primitives are used as they are: the layer,
// the popover, the notice, the count, the flag, the rail and its round check, and its memory (GkGui.get and set).
// Plain DOM, no jQuery. The words come from the page (data-* on the element, or the JSON element #gk-icons-texts).
(function () {
  var S = window.GkIcons, G = window.GkGui;
  // the script can be on a page twice (the library asks for it, and so does the editor's function)
  if (!S || S.started) return;
  S.started = true;
  var T = {};
  try { var tEl = document.getElementById('gk-icons-texts'); if (tEl) T = JSON.parse(tEl.textContent); } catch (e) { T = {}; }
  function t(k, d) { return T[k] || d; }
  // the mark an image's size is written with (the file stays ASCII)
  var TIMES = String.fromCharCode(215);
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }
  // The library's own choice (how a click copies) in GK GUI Stuff's memory, under the library's key as its other
  // choices; the key the icon library kept it under before is carried over once
  function remember(k, v) {
    var key = 'lib.icons.' + k;
    if (v !== undefined) { G.set(key, v); return null; }
    var now = G.get(key);
    if (now != null) return now;
    try {
      var was = window.localStorage.getItem('gk_icons.library.' + k);
      if (was != null) { G.set(key, was); window.localStorage.removeItem('gk_icons.library.' + k); }
      return was;
    } catch (e) { return null; /* no memory in this browser: the defaults hold */ }
  }
  // a template's content, cloned
  function fromTemplate(sel) { var tp = document.querySelector(sel); return tp ? tp.content.cloneNode(true) : null; }

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
  // how an icon is written in text: :fa/hammer:, and :gk/name: for core's and GK's own
  function own(i) { return i.group === 'core' || i.group === 'own'; }
  function inText(i) { return ':' + (own(i) ? 'gk/' + i.short : i.name) + ':'; }

  // an icon drawn as a shape in the text's colour where nothing of its own says otherwise (the library's small
  // pictures and Lista); a pack's own rule for its icons comes first (gk-icons-glyph is under :where in the CSS)
  function glyph(name, size) { var g = S.svg(name, size); g.classList.add('gk-icons-glyph'); return g; }
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
  // The Icons tab on GK GUI Stuff's library as data (window.GkGuiLibrary, gk_gui_stuff_library.js): the search field,
  // the chips, the grid or Lista, core's page numbers with Per sida, Sortera, the panel beside, the keys and the address
  // are the library's. This plugin gives it the icons and their parts: the small picture, the ranked search, the chips
  // (the packs, the installation's own groups and, for an administrator, the states), a click that copies the icon as
  // Ett klick kopierar says, the panel's content, the checked icons and the reload after a change. An administrator
  // (data-gk-icons-admin) sees every icon of the active packs, the ones disabled one by one greyed with a mark, checks
  // many and acts on them in the box above the library (the checkboxes show while that box is open), and changes an
  // icon's state in its panel; a disabled pack shows no icons and its chip is greyed and says where it is enabled.
  function library(root) {
    var L = window.GkGuiLibrary, host = root.querySelector('[data-gk-gui-lib]');
    if (!L || !host) return;
    var admin = root.dataset.gkIconsAdmin === '1';
    function part(n) { return root.querySelector('[data-gk-icons="' + n + '"]'); }
    var selCount = part('selcount'), selGroup = part('selgroup'), formSel = part('form');
    var all = [], packOn = {}, lib = null, marking = false;
    // the choices the icon library kept under its own keys before it moved to the library: carried over once into GK
    // GUI Stuff's memory (GkGui.get and set), under the library's keys
    try {
      var ls = window.localStorage, key = host.getAttribute('data-gk-gui-lib');
      [['view', 'view.lib.view.' + key], ['per', 'lib.' + key + '.per'], ['sort', 'lib.' + key + '.sort']].forEach(function (p) {
        var was = ls.getItem('gk_icons.library.' + p[0]);
        if (was == null) return;
        if (G.get(p[1]) == null) G.set(p[1], was);
        ls.removeItem('gk_icons.library.' + p[0]);
      });
    } catch (e) { /* no memory in this browser */ }
    if (formSel && ['text', 'name'].indexOf(remember('form')) >= 0) formSel.value = remember('form');
    if (formSel) formSel.addEventListener('change', function () { remember('form', formSel.value); });
    function form() { return formSel && formSel.value === 'name' ? 'name' : 'text'; }
    // What a save or a reading said: GK GUI Stuff's notice, alarm for a refusal
    function tell(text, level) { G.notice.show({ level: level || 'info', text: text }); }
    function refused(j) { tell(j.error || String(j.status), 'alarm'); }
    // how many are checked: the words and GK GUI Stuff's count
    function paintSel() {
      if (!selCount || !lib) return;
      selCount.textContent = '';
      selCount.appendChild(document.createTextNode(t('selected', 'Checked') + ' '));
      selCount.appendChild(G.count({ n: lib.selected().length }));
    }
    function visible() {
      // a disabled pack lists no icons, not for an administrator either
      return all.filter(function (i) { return packOn[i.group] !== false; });
    }
    function groupLabel(k) {
      var g = (all.groups || []).filter(function (x) { return x.key === k; })[0];
      return g ? g.label : k;
    }
    // An icon's state says something about the icon and does nothing: GK GUI Stuff's flag (a fixed state) in the
    // state's role, as { text, role } for GkGui.flag.put and the library's facts
    function stateFlag(st) {
      return { text: t('state_' + st, st), role: { active: 'notice', disabled: 'tip' }[st] || 'warning' };
    }
    // The chips: Alla, the installation's own groups (dashed; their state in brackets for an administrator), the packs
    // (a disabled one greyed, not to be chosen, saying where it is enabled), and for an administrator the states
    function rows(items) {
      var groups = [{ value: '', label: t('all', 'All'), count: items.length }];
      (all.sets || []).forEach(function (s) {
        groups.push({ value: s.key, label: s.label + (admin && s.state !== 'active' ? ' [' + t('state_' + s.state, s.state) + ']' : ''), count: s.count, dashed: true });
      });
      (all.groups || []).forEach(function (g) {
        if (packOn[g.key] === false) groups.push({ value: g.key, label: g.label + ' [' + t('state_' + g.state, g.state) + ']', disabled: true, reason: t('pack_off', '') });
        else groups.push({ value: g.key, label: g.label, count: g.count });
      });
      var out = [{ key: 'group', label: t('pack_or_group', ''), chips: groups, filter: function (i, v) {
        if (v.indexOf('set:') === 0) { var s = setOf(all.sets, v); return !!(s && s.refs[i.name]); }
        return i.group === v;
      } }];
      if (admin) {
        var states = [];
        [['', t('all_states', 'All states')], ['disabled', t('only_disabled', 'Disabled')], ['missing', t('only_missing', 'Missing on disk')]].forEach(function (p) {
          var n = items.filter(function (i) { return !p[0] || i.state === p[0]; }).length;
          if (p[0] === 'missing' && !n) return;
          states.push({ value: p[0], label: p[1], count: n });
        });
        out.push({ key: 'state', label: t('state', 'State'), chips: states, filter: function (i, v) { return i.state === v; } });
      }
      return out;
    }
    // The checkboxes are for the box Checked icons (GK GUI Stuff's box of choices): they show while it is open.
    // Folding the box unchecks every icon, so nothing stays checked out of sight.
    function boxOpen() {
      var box = root.querySelector('[data-gk-gui-stuff-box="icons.selection"]');
      return !!box && !(box.classList.contains('collapsible') && box.classList.contains('collapsed'));
    }
    function watchBox() {
      var on = admin && boxOpen();
      if (marking && !on && lib && lib.selected().length) { marking = on; lib.clearSelection(); return; }
      marking = on;
      if (lib) lib.checking();
    }
    // The groups an icon is in, set at once (an icon of a pack, Redmine's or GK's alike): a rail per group with GK GUI
    // Stuff's round check, from the server's template; the icon goes in each rail's address, and the rail says Sparar,
    // Sparat or Inte sparat (a refusal also as a notice) and puts the check back when it was not saved
    function groupBoxes(i) {
      var box = el('p', 'gk-icons-panel-groups');
      box.appendChild(el('strong', null, t('groups', 'Groups') + ': '));
      var rails = fromTemplate('template[data-gk-icons="group-rails"]');
      var list = rails ? [].slice.call(rails.querySelectorAll('[data-gk-icons-group]')) : [];
      if (!list.length) { box.appendChild(el('em', 'info', t('no_groups', 'No groups yet'))); return box; }
      list.forEach(function (rail) {
        var s = setOf(all.sets, 'set:' + rail.getAttribute('data-gk-icons-group'));
        var check = rail.querySelector('[data-gk-gui-save-name="member"]');
        if (!s || !check) return;
        rail.setAttribute('data-gk-gui-save-url', rail.getAttribute('data-gk-gui-save-url') + '?ref=' + encodeURIComponent(i.name));
        check.setAttribute('aria-checked', s.refs[i.name] ? 'true' : 'false');
        rail.addEventListener('gk-gui-saved', function () {
          var on = check.getAttribute('aria-checked') === 'true';
          if (on && !s.refs[i.name]) { s.refs[i.name] = 1; s.count += 1; } else if (!on && s.refs[i.name]) { delete s.refs[i.name]; s.count -= 1; }
          forget(); lib.refresh();
        });
        box.appendChild(rail); box.appendChild(document.createTextNode(' '));
      });
      return box;
    }
    // The large picture by the icon's own aspect: a square stays 128 px, a wide or a tall one fills the preview box as
    // far as it goes on its long side (as object-fit: contain), so a 5:1 icon uses the box's width
    function fit(box, w, h) {
      var n = box.firstElementChild; if (!n) return;
      var maxW = Math.max(128, box.clientWidth - 40), maxH = Math.max(128, box.clientHeight - 40);
      var s = Math.min(maxW / w, maxH / h, 128 / Math.min(w, h));
      var bw = Math.round(w * s), bh = Math.round(h * s);
      if (n.tagName.toLowerCase() === 'svg') { n.setAttribute('width', bw); n.setAttribute('height', bh); }
      n.style.inlineSize = bw + 'px'; n.style.blockSize = bh + 'px';
    }
    // width x height from the icon's own file: an svg's viewBox (or width and height), a png's size
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
    // The state form of a pack's icon in GK GUI Stuff's popover at Change the state...: the state in a select, Spara and
    // Avbryt side by side, and the reason (the place icons.choose) on its own line under them, from the server's
    // template; a required reason left empty stops Spara in the box (the popover's own check), and nothing is saved
    // before Spara. A save that went through closes the box and says so in a notice.
    function stateForm(i, opener) {
      var content = fromTemplate('template[data-gk-icons="state"]');
      if (!content) return;
      var f = content.querySelector('form'), sel = f.querySelector('select[name="chosen"]'), b = f.querySelector('[type="submit"]');
      sel.value = i.state === 'disabled' ? 'disabled' : 'active';
      var d = G.popover.open(opener, content);
      f.addEventListener('submit', function (e) {
        if (e.defaultPrevented) return;
        e.preventDefault();
        var r = f.querySelector('[name="reason"]');
        if (sel.value === i.state) { tell(t('unchanged', 'The state is already that; nothing was saved.')); return; }
        b.disabled = true;
        post(root.dataset.gkIconsChooseUrl, { ref: i.name, chosen: sel.value, reason: r ? r.value : '', whole_pack: '0' }).then(function (j) {
          b.disabled = false;
          if (!j.ok) { refused(j); return; }
          G.popover.close(d);
          tell(t('saved', 'Saved') + ': ' + i.name, 'notice');
          forget(); lib.reload(true);
        });
      });
      sel.focus();
    }
    // The panel's content under the library's head (the name with the state's flag, and the cross): large, then at the
    // sizes it is drawn at as small tiles, its aspect ratio, how it is written as the library's code fields, its pack,
    // its groups, the way to change its state (the state itself is the flag on the name), and icons with a similar name
    function panel(i, box) {
      var big = el('div', 'gk-gui-stuff-lib-preview gk-gui-stuff-lib-canvas gk-icons-preview'); big.appendChild(S.svg(i.name, 128)); box.appendChild(big);
      var sizes = el('div', 'gk-gui-stuff-lib-states gk-icons-sizes');
      [16, 24, 32, 48].forEach(function (n) {
        var fg = el('figure', 'gk-gui-stuff-lib-state'), cv = el('div', 'gk-gui-stuff-lib-canvas');
        cv.appendChild(S.svg(i.name, n)); fg.appendChild(cv); fg.appendChild(el('figcaption', null, n + ' px')); sizes.appendChild(fg);
      });
      box.appendChild(sizes);
      var rt = el('p', 'gk-icons-ratio'); box.appendChild(rt);
      ratio(i, rt, function (w, h) { if (lib.openKey() === i.name) fit(big, w, h); });
      box.appendChild(lib.code(t('name', 'Name'), i.name));
      box.appendChild(lib.code(t('in_text', 'Used in text'), inText(i)));
      box.appendChild(lib.code(t('in_code', 'In a plugin'), "gk_icon('" + i.name + "')"));
      // the pack, and for a pack's icon the way to the whole pack's state
      var pk = el('p');
      pk.appendChild(el('strong', null, t('pack', 'Pack') + ': '));
      pk.appendChild(document.createTextNode(groupLabel(i.group) + ' '));
      if (admin && !own(i)) {
        var a = el('a', null, t('pack_change', 'The whole pack is changed under the tab Packs')); a.href = root.dataset.gkIconsPacksUrl + '#gk-icons-pack-' + i.group;
        pk.appendChild(a);
      }
      box.appendChild(pk);
      if (admin) {
        box.appendChild(groupBoxes(i));
        // The state is said once: as the flag on the name in the library's head, never again
        // as a line here; what stays is the way to change it
        if (own(i)) {
          // Redmine's icons and GK's are used by Redmine and the plugins themselves: they have no state to change
          box.appendChild(el('p', 'info', t('cannot_disable', "Redmine's icons and GK's icons cannot be disabled: Redmine and the plugins use them.")));
        } else {
          if (i.state === 'missing') box.appendChild(el('p', 'info', t('missing_info', 'The file is no longer on disk.') + ' ' + t('missing_choose', '')));
          var stp = el('p', 'gk-icons-change-state'), open0 = el('a', null, t('change_state', 'Change the state...')); open0.href = '#';
          open0.addEventListener('click', function (e) { e.preventDefault(); stateForm(i, open0); });
          stp.appendChild(open0); box.appendChild(stp);
        }
      } else {
        var mine = (all.sets || []).filter(function (s) { return s.refs[i.name]; }).map(function (s) { return s.label; });
        if (mine.length) { var gp = el('p'); gp.appendChild(el('strong', null, t('groups', 'Groups') + ': ')); gp.appendChild(document.createTextNode(mine.join(', '))); box.appendChild(gp); }
      }
      var like = similar(i);
      if (like.length) {
        box.appendChild(el('h4', null, t('similar', 'Similar icons')));
        var sg = el('div', 'gk-icons-similar');
        like.forEach(function (j) { var b = cell(j, 24); b.addEventListener('click', function () { lib.open(j.name); }); sg.appendChild(b); });
        box.appendChild(sg);
      }
    }
    // The box above the library: the checked ones at once
    function many(url, data, done) {
      var refs = lib.selected();
      if (!refs.length) { tell(t('none_marked', 'Check icons first')); return; }
      var body = new URLSearchParams();
      Object.keys(data).forEach(function (k) { body.append(k, data[k]); });
      refs.forEach(function (r) { body.append('refs[]', r); });
      post(url, body).then(function (j) {
        if (!j.ok) { refused(j); return; }
        tell(t('changed', '%{n} changed').replace('%{n}', j.changed) + (j.skipped ? ', ' + t('skipped', '%{n} unchanged').replace('%{n}', j.skipped) : ''));
        if (done) done();
        forget(); lib.reload(true);
      });
    }
    // after a save that went through: the box of the button with the reason closed, and its reason empty again
    function fresh(f) {
      var r = f.querySelector('[name="reason"]'); if (r) r.value = '';
      f.querySelectorAll('details.gk-gui-stuff-popover[open]').forEach(function (d) { G.popover.close(d); });
    }
    function wireBox() {
      function on(name, fn) { var b = part(name); if (b) b.addEventListener('click', function (e) { e.preventDefault(); fn(); }); }
      on('sel-all', function () { lib.selectHits(); });
      on('sel-none', function () { lib.clearSelection(); });
      var stateF = part('sel-state'), groupF = part('sel-group');
      if (stateF) {
        stateF.addEventListener('submit', function (e) {
          if (e.defaultPrevented) return;
          e.preventDefault();
          // core marks a form sent (data-submitted) and refuses the next send, also when this one was stopped here
          setTimeout(function () { stateF.removeAttribute('data-submitted'); }, 0);
          // the state chosen in the select is saved for every checked icon by Spara (GK GUI Stuff's button with the
          // reason; a required reason left empty is stopped in its box before the form is sent)
          var r = stateF.querySelector('[name="reason"]'), ch = stateF.querySelector('select[name="chosen"]');
          if (!ch || !ch.value) { if (ch) ch.focus(); return; }
          many(root.dataset.gkIconsChooseManyUrl, { chosen: ch.value, reason: r ? r.value : '' },
               function () { lib.clearSelection(); ch.value = ''; fresh(stateF); });
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
    var refreshF = part('refresh');
    if (refreshF) {
      refreshF.addEventListener('submit', function (e) {
        e.preventDefault();
        var btn = refreshF.querySelector('[type="submit"]');
        if (btn) btn.disabled = true;
        tell(t('refreshing', 'Reading the pack folders...'));
        post(refreshF.action, {}).then(function (j) {
          if (btn) btn.disabled = false;
          if (!j.ok) { refused(j); return; }
          var c = j.counts || {};
          tell(t('refreshed', 'Read: %{added} new, %{changed} changed, %{missing} missing on disk, %{unchanged} unchanged')
            .replace('%{added}', c.added || 0).replace('%{changed}', c.changed || 0)
            .replace('%{missing}', c.missing || 0).replace('%{unchanged}', c.unchanged || 0), 'notice');
          forget(); lib.reload(true);
        });
      });
    }
    marking = admin && boxOpen();
    lib = L.bind(host, {
      load: function () {
        return list(admin).then(function (a) {
          all = a; packOn = {};
          (a.groups || []).forEach(function (g) { packOn[g.key] = g.state === 'active'; });
          return visible();
        });
      },
      key: function (i) { return i.name; },
      // the whole name (pack/name) in the panel, Lista and the box to check; the short one under the picture
      name: function (i) { return i.name; },
      tile: function (i) { return i.short; },
      anchor: function (i) { return 'gk-icon-' + i.name; },
      words: function (i) { return i.low; },
      group: function (i) { return i.group; },
      // not by colour alone: the state in the tooltip and as the item's flag with its word (the short form, the word
      // on hover; the screen reader hears it with the item), for the eye and the screen reader
      title: function (i) { return admin && i.state !== 'active' ? i.name + ': ' + t('mark_' + i.state, t('state_' + i.state, i.state)) : i.name; },
      thumb: function (i) { return glyph(i.name, 28); },
      decorate: function (i, node) {
        var box = node.querySelector('[data-gk-gui-lib-check]');
        if (box) box.title = t('mark_title', '');
        if (!admin || i.state === 'active') return;
        node.classList.add('gk-icons-state-' + i.state);
        var f = stateFlag(i.state);
        G.flag.put(node, f.text, { role: f.role, short: true });
      },
      facts: function (i) { return admin ? [stateFlag(i.state)] : []; },
      panel: panel,
      // the ranked search: exact names first, then a name that is one of the words, then one that starts with the first
      search: function (items, q) { return search(items, q, '', all.sets); },
      sort: function (items, how) {
        if (how === 'group') return items; // the server's order: Redmine, GK's, then each pack, each by name
        var out = items.slice().sort(function (a, b) { return a.short.localeCompare(b.short) || a.name.localeCompare(b.name); });
        return how === 'name_desc' ? out.reverse() : out;
      },
      rows: rows,
      cell: function (i, col) {
        if (col === 'picture') return glyph(i.name, 24);
        if (col === 'group') return groupLabel(i.group);
        // the state in its column is GK GUI Stuff's flag as an element of its own, the word after the pennant in the
        // state's role, as on the name in the panel
        if (col === 'state') {
          var sf = stateFlag(i.state);
          return G.flag.inline(sf.text, { role: sf.role });
        }
        return null;
      },
      check: function () { return admin && marking; },
      onSelect: paintSel,
      // A click on an icon: copied as Ett klick kopierar says, "Kopierat" at the icon, and the icon in the panel
      onPick: function (i, node) { lib.copy(form() === 'name' ? i.name : inText(i), form() === 'name' ? t('name', 'Name') : t('in_text', 'Used in text'), node); },
      focusSearch: true
    });
    paintSel();
    if (admin) {
      var selBox = root.querySelector('[data-gk-gui-stuff-box="icons.selection"]');
      if (selBox && window.MutationObserver) new MutationObserver(watchBox).observe(selBox, { attributes: true, attributeFilter: ['class'] });
      wireBox();
    }
  }

  // ------------------------------------------------------------------ the Packs tab: height, place and space in text
  // A row's button opens GK GUI Stuff's popover (GkGui.popover) with the form of the page's template: the values in
  // use, the pack's first icon in three sizes of text, Spara and Avbryt side by side and the reason (the place
  // icons.text_fit) on its own line under them. The icons follow the fields while they are changed, and Spara sends the
  // form (the server goes back to the tab with its message). A cleared field shows the pack's own value (its
  // placeholder), which is also what the server keeps for it.
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
    if (!a) return;
    var content = fromTemplate('template[data-gk-icons="fit"]');
    if (!content) return;
    e.preventDefault();
    var d = a.dataset, form = content.querySelector('form');
    form.action = d.url;
    var title = form.querySelector('[data-gk-icons-fit-title]');
    if (title) title.textContent = title.textContent + ': ' + d.name;
    FIT.forEach(function (k) {
      var f = form.querySelector('[data-gk-icons-fit="' + k + '"]'), K = k.charAt(0).toUpperCase() + k.slice(1);
      f.value = d[k] != null ? d[k] : ''; f.placeholder = d['ph' + K] != null ? d['ph' + K] : '';
      fitStep(f, f.value);
    });
    var tpl = document.querySelector('template[data-gk-icons-fit-sample="' + d.gkIconsFitOpen + '"]');
    form.querySelectorAll('[data-gk-icons-fit-slot]').forEach(function (slot) {
      slot.textContent = '';
      if (tpl) slot.appendChild(tpl.content.cloneNode(true));
    });
    fitPaint(form);
    G.popover.open(a, content, { className: 'gk-icons-fit-popover' });
  });
  document.addEventListener('input', function (e) {
    var f = e.target.closest && e.target.closest('[data-gk-icons-fit]');
    if (f && f.form) fitPaint(f.form);
  });

  // ------------------------------------------------------------------ the picker's surface (the picker and the editor)
  // GK GUI Stuff's surface in the upper layer (GkGui.layer): under its button, moving nothing, a sheet at the bottom of
  // the window below 899 px; Esc, its cross and a press outside close it, and the focus goes back to the button (the
  // editor's: to its text area). Over a popover or a layer the picker stands in, it is lifted above it.
  var KEY = 'gk-icons-picker', pop = null;
  function close() { if (pop) { var p = pop; pop = null; p.layer.close(false); } }
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
    var over = anchor.closest('.gk-gui-stuff-layer, .gk-gui-stuff-popover-box');
    var layer = G.layer.open({ key: KEY, content: p, anchor: anchor, opener: anchor, above: over ? anchor : null,
                               onClose: function (why) {
                                 if (pop && pop.el === p) pop = null;
                                 if (back !== anchor && (why === 'escape' || why === 'x')) back.focus();
                               } });
    pop = { el: p, anchor: anchor, layer: layer };
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
      layer.place();
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
    // the field set back from outside (a form's Undo all) says so with a change: the button follows
    input.addEventListener('change', paint);
    b.addEventListener('click', function () { if (pop && pop.anchor === b) close(); else open(b, chosen, { current: input.value, none: true }); });
    input.type = 'hidden';
    input.insertAdjacentElement('afterend', b);
    paint();
  }

  // ------------------------------------------------------------------ the editor's toolbar (icons.editor_insert)
  // A tool in core's jsToolBar (the same in Redmine 6.0 to 7.0, textile and common_mark): jsToolBar.prototype.elements,
  // drawn by each toolbar's draw(). It stands before core's Help, as core's own tools do. A toolbar drawn before this
  // script ran gets the same button put in its row, drawn by core's own jsButton (its icon as core draws a tool's).
  var TOOL = 'gk_icons_insert', SPACE = 'gk_icons_insert_space';
  // the tool's own space in a row drawn earlier: core's jsSpace, as core's draw makes one, else its span
  function space() {
    if (typeof window.jsSpace === 'function') { var s = new window.jsSpace(SPACE).draw(); if (s) return s; }
    return el('span', 'jstSpacer ' + SPACE, String.fromCharCode(160));
  }
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
      // the tool and a space of its own stand just before core's Help (its key help); every other element keeps its
      // place, so nothing depends on what core puts before Help
      var keys = Object.keys(els), at = keys.indexOf('help');
      var tail = at >= 0 ? keys.slice(at) : [], kept = {};
      tail.forEach(function (k) { kept[k] = els[k]; delete els[k]; });
      els[TOOL] = { type: 'button', title: label, icon: icon,
                    fn: { wiki: function () { openFor(this.toolNodes[TOOL], this.textarea); } } };
      if (tail.length) els[SPACE] = { type: 'space' };
      tail.forEach(function (k) { els[k] = kept[k]; });
    }
    // A toolbar drawn before this script ran: core's block for it (.jstBlock, jsToolBar's toolbarBlock) holds its row
    // of tools (.jstElements) and its editor (.jstEditor) with the text area; both are looked up inside the block
    if (typeof window.jsButton !== 'function') return;
    document.querySelectorAll('.jstBlock').forEach(function (block) {
      var bar = block.querySelector('.jstElements'), ta = block.querySelector('.jstEditor textarea');
      if (!bar || !ta || bar.querySelector('.jstb_' + TOOL)) return;
      var b = null, tool = new window.jsButton(label, function () { openFor(b, ta); }, block, 'jstb_' + TOOL);
      tool.icon = icon;
      b = tool.draw();
      if (!b) return;
      // just before core's Help button (jstb_help, the class core's draw gives the tool help), with the same own space
      // as above; without Help, last in the row
      var help = bar.querySelector('.jstb_help');
      bar.insertBefore(b, help);
      if (help) bar.insertBefore(space(), help);
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
