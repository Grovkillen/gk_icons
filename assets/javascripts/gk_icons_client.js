// gk_icons client: the browser's way to the same icons the helper draws, on every page (the hook in core.rb loads it
// in the head, right after its settings, so window.GkIcons is there before any other script asks for it).
//   GkIcons.svg(name, size, one)   an element that draws the icon (core's or GK's sprite, a pack's sprite or its file)
//   GkIcons.url(name)              the icon as a file of its own (for a mask or a background)
//   GkIcons.own(name)              true for an icon of GK's own sprite
//   GkIcons.namesUrl, .editorInsert, .chunks, .load(url)
// The settings are data in the JSON element #gk-icons-config (core.rb): the sprites' addresses, GK's own names, the
// stamps, the packs and whether a click on an icon in text copies its code (copy: the whisper's words).
// Plain DOM, no jQuery.
(function () {
  var cfgEl = document.getElementById('gk-icons-config');
  var c = null;
  try { c = cfgEl ? JSON.parse(cfgEl.textContent) : null; } catch (e) { c = null; }
  if (!c || window.GkIcons) return;
  var own = {}; (c.names || []).forEach(function (n) { own[n] = 1; });
  var NS = 'http://www.w3.org/2000/svg';
  c.packs = c.packs || {};
  window.GkIcons = {
    namesUrl: c.namesUrl,
    // the editor's button (icons.editor_insert) is drawn only while the function is on
    editorInsert: !!c.editorInsert,
    own: function (n) { return !!own[n]; },
    url: function (n) {
      if (n.indexOf('/') < 0) return c.one + n + '.svg?v=' + c.v;
      var k = n.split('/')[0], p = c.packs[k];
      return c.pack + k + '/' + encodeURIComponent(n.slice(k.length + 1)) + (p && !p.svg ? '.png' : '.svg') + '?v=' + c.pv;
    },
    chunks: {},
    // A sprite is fetched before any icon points into it, at most two at a time, and again when it fails (the
    // server answered 500 when many were built at once, and the browser never asks again for a sprite a <use>
    // could not load); known: the symbols it holds, so an icon left out is fetched by itself
    loads: {}, queue: [], busy: 0,
    load: function (url) {
      var self = this;
      if (!this.loads[url]) {
        this.loads[url] = new Promise(function (resolve, reject) { self.queue.push({ url: url, resolve: resolve, reject: reject, tries: 0 }); self.pump(); });
      }
      return this.loads[url];
    },
    pump: function () {
      var self = this;
      while (this.busy < 2 && this.queue.length) {
        var job = this.queue.shift();
        this.busy += 1;
        fetch(job.url, { credentials: 'same-origin' }).then(function (r) {
          if (!r.ok) throw new Error(String(r.status));
          return r.text();
        }).then(function (text) {
          var ids = {}; text.replace(/<symbol id="([^"]+)"/g, function (m, id) { ids[id] = 1; return m; });
          this.resolve(ids);
        }.bind(job), function () {
          var j = this;
          j.tries += 1;
          if (j.tries < 3) { setTimeout(function () { self.queue.push(j); self.pump(); }, 700 * j.tries); } else { j.reject(); }
        }.bind(job)).then(function () { self.busy -= 1; self.pump(); });
      }
    },
    // one: the icon's own file, never the sprite
    svg: function (n, size, one) {
      if (!one && n.indexOf('/') >= 0 && c.sprite && this.chunks[n] != null) {
        // From the pack's sprite, the chunk known from the list of names
        var k0 = n.split('/')[0], pk0 = c.packs[k0], sv = document.createElementNS(NS, 'svg'), us = document.createElementNS(NS, 'use');
        var sid = ('i-' + k0 + '-' + n.slice(k0.length + 1)).replace(/[^A-Za-z0-9_.-]/g, '_');
        sv.setAttribute('class', 'gk-icon s' + (size || 18) + ' ' + (pk0 && pk0.mono ? 'gk-icon-mono' : 'gk-icon-colour'));
        sv.setAttribute('width', size || 18); sv.setAttribute('height', size || 18); sv.setAttribute('aria-hidden', 'true');
        var url = c.sprite + k0 + '/' + this.chunks[n] + '.svg?v=' + c.sv, self = this;
        sv.appendChild(us);
        this.load(url).then(function (ids) {
          if (ids[sid]) { us.setAttribute('href', url + '#' + sid); return; }
          if (sv.parentNode) sv.parentNode.replaceChild(self.svg(n, size, true), sv);
        }, function () { if (sv.parentNode) sv.parentNode.replaceChild(self.svg(n, size, true), sv); });
        return sv;
      }
      if (n.indexOf('/') >= 0) {
        var pk = c.packs[n.split('/')[0]], e = document.createElement('span');
        e.className = 'gk-icon s' + (size || 18) + ' ' + (pk && pk.mono ? 'gk-icon-mono' : 'gk-icon-colour');
        e.style.setProperty('--gk-icon', 'url(' + this.url(n) + ')');
        e.style.inlineSize = e.style.blockSize = (size || 18) + 'px'; e.setAttribute('aria-hidden', 'true');
        return e;
      }
      var s = document.createElementNS(NS, 'svg'), u = document.createElementNS(NS, 'use');
      s.setAttribute('class', 's' + (size || 18) + ' icon-svg'); s.setAttribute('aria-hidden', 'true');
      // core's stylesheet sizes only some s-classes (s18, s24): the size as attributes too
      s.setAttribute('width', size || 18); s.setAttribute('height', size || 18);
      u.setAttribute('href', (own[n] ? c.own : c.core) + '#icon--' + n);
      s.appendChild(u);
      return s;
    }
  };

  // A click on an icon in formatted text (an issue, a note, a wiki page) copies its code, :pack/name:, so that an icon
  // found anywhere can be put in a note; an icon inside a link, an editor or a text area is left alone. GK GUI
  // Stuff's shared copy says it with its whisper under the icon, and closes core's hover tooltip first, so that the two
  // never stand on top of each other. Only while Icons in text is on for the person (c.copy, the whisper's words).
  if (!c.copy) return;
  document.documentElement.classList.add('gk-icons-copy');
  var SEL = 'span.gk-icon-in-text[title], span.gk-icon-in-text[data-gk-icons-code]';
  // The code is the span's data-gk-icons-code (gk_icon_in_text); a text formatted before it had one gives its title.
  // Core's tooltip empties the title while it shows, so the title is kept as the code when the pointer or the focus
  // comes, in the capture phase, before the tooltip (bound at the document) takes it
  function keep(e) {
    var s = e.target.closest && e.target.closest(SEL);
    if (s && !s.hasAttribute('data-gk-icons-code') && s.getAttribute('title')) s.setAttribute('data-gk-icons-code', s.getAttribute('title'));
  }
  document.addEventListener('mouseover', keep, true);
  document.addEventListener('focusin', keep, true);
  document.addEventListener('click', function (e) {
    var s = e.target.closest && e.target.closest(SEL);
    if (!s || s.closest('a, .jstEditor, textarea')) return;
    var code = s.getAttribute('data-gk-icons-code') || s.getAttribute('title');
    if (!code) return;
    window.GkGui.copy(':' + code + ':', c.copy, s);
  });
})();
