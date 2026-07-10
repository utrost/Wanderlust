// Builds the "Wanderlust — Mood & Map" visual-direction canvas.
// Faithful port of "Wanderlust Mood & Map.dc.html" from the Claude Design
// handoff bundle: the proprietary <x-dc> template directives (sc-for, sc-if,
// x-import and {{ }} bindings) are replaced with plain DOM string assembly.
(function () {
  'use strict';

  var M = window.MapData;
  var frame = window.androidFrame;
  var S = M.STREET_SEGMENTS;

  // ── shared generators ──────────────────────────────────────────────────────
  function segPaths(key, opt) {
    opt = opt || {};
    var dark = !!opt.dark;
    var op = opt.opacity;
    var opAttr = (op != null) ? ' opacity="' + op + '"' : '';
    var out = '';
    for (var i = 0; i < S.length; i++) {
      var s = S[i];
      if (s[key] <= 0) continue;
      var w = M.rampWidth(s[key]);
      if (dark) {
        out += '<path d="' + s.d + '" stroke="' + M.rampColor(s[key], true) + '" stroke-width="' + w +
               '" fill="none" stroke-linecap="round" style="filter:' + M.rampGlow(s[key], true) + ';"' + opAttr + '></path>';
      } else {
        out += '<path d="' + s.d + '" stroke="' + M.rampColor(s[key], false) + '" stroke-width="' + w +
               '" fill="none" stroke-linecap="round"' + opAttr + '></path>';
      }
    }
    return out;
  }

  var heroLevels = [
    { label: 'First week',       percent: 6,  key: 'week',  sparkle: true,  claimed: false },
    { label: 'A few months in',  percent: 50, key: 'month', sparkle: false, claimed: false },
    { label: 'Two years in',     percent: 91, key: 'year',  sparkle: false, claimed: true }
  ];

  // ── Foundations: the walk-count ramp ───────────────────────────────────────
  function rampSwatches() {
    var counts = [1, 3, 10, 30, 100, 300, 1000];
    return counts.map(function (count, i) {
      return {
        count: count,
        x: 20 + i * (600 / (counts.length - 1)),
        width: M.rampWidth(count),
        lightColor: M.rampColor(count, false),
        darkColor: M.rampColor(count, true),
        darkGlow: M.rampGlow(count, true)
      };
    });
  }

  function rampLines(sw, colorKey, glow, y1, y2) {
    return sw.map(function (s) {
      var style = glow ? ' style="filter:' + s.darkGlow + ';"' : '';
      return '<line x1="' + s.x + '" y1="' + y1 + '" x2="' + s.x + '" y2="' + y2 +
             '" stroke="' + s[colorKey] + '" stroke-width="' + s.width + '" stroke-linecap="round"' + style + '></line>';
    }).join('');
  }
  function rampLabels(sw, color) {
    return sw.map(function (s) {
      return '<span style="font-size:12px; font-variant-numeric:tabular-nums; color:' + color + ';">' + s.count + '×</span>';
    }).join('');
  }

  function foundations() {
    var sw = rampSwatches();
    return '' +
    '<div style="background:#FBF8F2; border:1px solid oklch(0.9 0.01 75); border-radius:20px; padding:44px 48px; margin-bottom:72px;">' +
      '<div style="font-family:\'Newsreader\',serif; font-size:24px; font-weight:500; margin-bottom:6px;">Foundations</div>' +
      '<div style="font-size:14px; color:oklch(0.5 0.02 75); margin-bottom:36px;">Colour ramp, basemap tones, and type — the ingredients the map is built from.</div>' +

      '<div style="font-size:12px; font-weight:600; letter-spacing:0.08em; text-transform:uppercase; color:oklch(0.5 0.02 75); margin-bottom:14px;">The walk-count ramp &nbsp;— &nbsp;<span style="font-weight:400; text-transform:none; letter-spacing:0; font-style:italic; font-family:\'Newsreader\',serif; font-size:14px;">faint at 1×, ink-dark near 1000× — logarithmic, since a real walking life spans orders of magnitude. Width always carries the signal too.</span></div>' +

      '<div style="display:flex; gap:28px; margin-bottom:18px;">' +
        '<div style="flex:1; background:oklch(0.95 0.012 80); border-radius:12px; padding:22px 26px 16px;">' +
          '<div style="font-size:11px; font-weight:600; letter-spacing:0.06em; text-transform:uppercase; color:oklch(0.5 0.02 75); margin-bottom:14px;">On light paper</div>' +
          '<svg viewBox="0 0 640 60" style="width:100%; height:60px; display:block;">' + rampLines(sw, 'lightColor', false, 14, 44) + '</svg>' +
          '<div style="display:flex; justify-content:space-between; padding:0 2px;">' + rampLabels(sw, 'oklch(0.5 0.02 75)') + '</div>' +
        '</div>' +
        '<div style="flex:1; background:oklch(0.22 0.014 75); border-radius:12px; padding:22px 26px 16px;">' +
          '<div style="font-size:11px; font-weight:600; letter-spacing:0.06em; text-transform:uppercase; color:oklch(0.7 0.02 80); margin-bottom:14px;">On dark paper</div>' +
          '<svg viewBox="0 0 640 60" style="width:100%; height:60px; display:block;">' + rampLines(sw, 'darkColor', true, 14, 44) + '</svg>' +
          '<div style="display:flex; justify-content:space-between; padding:0 2px;">' + rampLabels(sw, 'oklch(0.7 0.02 80)') + '</div>' +
        '</div>' +
      '</div>' +

      '<div style="display:flex; gap:28px; margin-bottom:40px;">' +
        '<div style="flex:1; background:oklch(0.95 0.012 80); border-radius:12px; padding:14px 26px;">' +
          '<svg viewBox="0 0 640 40" style="width:100%; height:40px; display:block; filter:grayscale(1);">' + rampLines(sw, 'lightColor', false, 8, 32) + '</svg>' +
          '<div style="font-size:11.5px; color:oklch(0.5 0.02 75); margin-top:8px;">Colour-vision check (desaturated) — still reads as a clean intensity ramp, because width and lightness carry it, not hue alone.</div>' +
        '</div>' +
      '</div>' +

      '<div style="display:flex; gap:40px; flex-wrap:wrap;">' +
        '<div style="flex:1; min-width:280px;">' +
          '<div style="font-size:12px; font-weight:600; letter-spacing:0.08em; text-transform:uppercase; color:oklch(0.5 0.02 75); margin-bottom:14px;">Basemap — quiet substrate</div>' +
          '<div style="display:flex; gap:16px;">' +
            '<div style="flex:1; border-radius:10px; overflow:hidden; border:1px solid oklch(0.88 0.01 75);">' +
              '<svg viewBox="0 0 200 120" style="width:100%; display:block; background:oklch(0.95 0.012 80);">' +
                '<path d="M0,90 Q60,60 110,95 T200,75" stroke="oklch(0.90 0.014 220)" stroke-width="16" fill="none"></path>' +
                '<ellipse cx="45" cy="30" rx="34" ry="20" fill="oklch(0.90 0.02 140)"></ellipse>' +
                '<line x1="20" y1="10" x2="20" y2="110" stroke="oklch(0.86 0.008 75)" stroke-width="1.4"></line>' +
                '<line x1="70" y1="10" x2="70" y2="110" stroke="oklch(0.86 0.008 75)" stroke-width="1.4"></line>' +
                '<line x1="120" y1="10" x2="120" y2="110" stroke="oklch(0.86 0.008 75)" stroke-width="1.4"></line>' +
                '<line x1="10" y1="40" x2="190" y2="40" stroke="oklch(0.86 0.008 75)" stroke-width="1.4"></line>' +
                '<line x1="10" y1="80" x2="190" y2="80" stroke="oklch(0.86 0.008 75)" stroke-width="1.4"></line>' +
              '</svg>' +
              '<div style="padding:8px 12px; font-size:12px; color:oklch(0.5 0.02 75);">Light</div>' +
            '</div>' +
            '<div style="flex:1; border-radius:10px; overflow:hidden; border:1px solid oklch(0.3 0.01 75);">' +
              '<svg viewBox="0 0 200 120" style="width:100%; display:block; background:oklch(0.22 0.014 75);">' +
                '<path d="M0,90 Q60,60 110,95 T200,75" stroke="oklch(0.27 0.02 230)" stroke-width="16" fill="none"></path>' +
                '<ellipse cx="45" cy="30" rx="34" ry="20" fill="oklch(0.26 0.02 140)"></ellipse>' +
                '<line x1="20" y1="10" x2="20" y2="110" stroke="oklch(0.32 0.012 75)" stroke-width="1.4"></line>' +
                '<line x1="70" y1="10" x2="70" y2="110" stroke="oklch(0.32 0.012 75)" stroke-width="1.4"></line>' +
                '<line x1="120" y1="10" x2="120" y2="110" stroke="oklch(0.32 0.012 75)" stroke-width="1.4"></line>' +
                '<line x1="10" y1="40" x2="190" y2="40" stroke="oklch(0.32 0.012 75)" stroke-width="1.4"></line>' +
                '<line x1="10" y1="80" x2="190" y2="80" stroke="oklch(0.32 0.012 75)" stroke-width="1.4"></line>' +
              '</svg>' +
              '<div style="padding:8px 12px; font-size:12px; color:oklch(0.7 0.02 80); background:oklch(0.22 0.014 75);">Dark</div>' +
            '</div>' +
          '</div>' +
        '</div>' +

        '<div style="flex:1.3; min-width:340px;">' +
          '<div style="font-size:12px; font-weight:600; letter-spacing:0.08em; text-transform:uppercase; color:oklch(0.5 0.02 75); margin-bottom:14px;">Type — a keepsake, not a scoreboard</div>' +
          '<div style="font-family:\'Newsreader\',serif; font-weight:500; font-size:28px; line-height:1.2; margin-bottom:8px;">Kreuzberg, two years in.</div>' +
          '<div style="font-size:15px; line-height:1.6; color:oklch(0.4 0.02 75); margin-bottom:14px; max-width:480px;">Work Sans for chrome and numbers, Newsreader for the moments that deserve a little warmth. Figures stay calm and tabular — never a scoreboard.</div>' +
          '<div style="display:flex; gap:28px; align-items:baseline;">' +
            '<div style="font-family:\'Work Sans\',sans-serif; font-variant-numeric:tabular-nums; font-weight:600; font-size:40px;">91%</div>' +
            '<div style="font-size:13px; color:oklch(0.5 0.02 75); max-width:150px; line-height:1.4;">of Kreuzberg walked, at your own pace</div>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  // ── The filling map: hero phones ───────────────────────────────────────────
  function claimedBadge(dark) {
    var star = dark ? 'oklch(0.7 0.12 55)' : 'oklch(0.42 0.1 45)';
    var ring = dark ? 'oklch(0.25 0.05 60)' : 'oklch(0.9 0.03 70)';
    return '<div style="position:absolute; top:64px; right:16px; width:38px; height:38px;">' +
      '<svg viewBox="0 0 40 40" width="38" height="38">' +
        '<path d="M20 1 L23.5 5 L28.5 3.5 L29.5 8.7 L34.8 9.5 L33 14.5 L37 18 L33 21.5 L34.8 26.5 L29.5 27.3 L28.5 32.5 L23.5 31 L20 35 L16.5 31 L11.5 32.5 L10.5 27.3 L5.2 26.5 L7 21.5 L3 18 L7 14.5 L5.2 9.5 L10.5 8.7 L11.5 3.5 L16.5 5 Z" fill="' + star + '"></path>' +
        '<circle cx="20" cy="18" r="8.5" fill="none" stroke="' + ring + '" stroke-width="1"></circle>' +
        '<path d="M16 18 L19 21 L25 14" stroke="' + ring + '" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"></path>' +
      '</svg></div>';
  }

  function startWalkPill(dark) {
    if (dark) {
      return '<div style="position:absolute; bottom:20px; left:0; right:0; display:flex; justify-content:center;">' +
        '<div style="display:flex; align-items:center; gap:8px; background:rgba(36,31,25,0.75); border:1px solid rgba(242,237,227,0.16); border-radius:100px; padding:11px 20px; box-shadow:0 6px 18px rgba(0,0,0,0.35);">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="oklch(0.78 0.12 55)" stroke-width="2" stroke-linecap="round"><path d="M13 4a2 2 0 1 0 0-4 2 2 0 0 0 0 4z" fill="oklch(0.78 0.12 55)" stroke="none"></path><path d="M9 21l1.5-5L8 14l1-5 4 1 2 3h3"></path><path d="M10 11l-2 3 3 2-1 5"></path></svg>' +
          '<span style="font-size:13px; font-weight:500; color:oklch(0.95 0.01 80);">Start walk</span>' +
        '</div></div>';
    }
    return '<div style="position:absolute; bottom:20px; left:0; right:0; display:flex; justify-content:center;">' +
      '<div style="display:flex; align-items:center; gap:8px; background:rgba(251,248,242,0.92); border:1px solid rgba(58,46,34,0.1); border-radius:100px; padding:11px 20px; box-shadow:0 6px 18px rgba(58,46,34,0.1);">' +
        '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="oklch(0.5 0.09 50)" stroke-width="2" stroke-linecap="round"><path d="M13 4a2 2 0 1 0 0-4 2 2 0 0 0 0 4z" fill="oklch(0.5 0.09 50)" stroke="none"></path><path d="M9 21l1.5-5L8 14l1-5 4 1 2 3h3"></path><path d="M10 11l-2 3 3 2-1 5"></path></svg>' +
        '<span style="font-size:13px; font-weight:500; color:oklch(0.3 0.03 75);">Start walk</span>' +
      '</div></div>';
  }

  function mapChip(dark) {
    if (dark) {
      return '<div style="position:absolute; top:16px; left:16px; right:16px; display:flex; justify-content:space-between; align-items:flex-start;">' +
        '<div style="background:rgba(36,31,25,0.7); backdrop-filter:blur(6px); border:1px solid rgba(242,237,227,0.14); border-radius:12px; padding:9px 14px;">' +
          '<div style="font-family:\'Newsreader\',serif; font-size:14px; font-weight:500; color:oklch(0.95 0.01 80);">Kreuzberg</div>' +
          '<div style="font-size:10.5px; color:oklch(0.7 0.02 80); margin-top:1px;">stays on your phone</div>' +
        '</div>' +
        '<div style="width:34px; height:34px; border-radius:50%; background:rgba(36,31,25,0.6); display:flex; align-items:center; justify-content:center;">' +
          '<svg width="15" height="15" viewBox="0 0 15 15"><circle cx="2" cy="7.5" r="1.4" fill="oklch(0.75 0.02 80)"></circle><circle cx="7.5" cy="7.5" r="1.4" fill="oklch(0.75 0.02 80)"></circle><circle cx="13" cy="7.5" r="1.4" fill="oklch(0.75 0.02 80)"></circle></svg>' +
        '</div></div>';
    }
    return '<div style="position:absolute; top:16px; left:16px; right:16px; display:flex; justify-content:space-between; align-items:flex-start;">' +
      '<div style="background:rgba(251,248,242,0.86); backdrop-filter:blur(6px); border:1px solid rgba(58,46,34,0.1); border-radius:12px; padding:9px 14px;">' +
        '<div style="font-family:\'Newsreader\',serif; font-size:14px; font-weight:500; color:oklch(0.25 0.02 75);">Kreuzberg</div>' +
        '<div style="font-size:10.5px; color:oklch(0.5 0.02 75); margin-top:1px;">stays on your phone</div>' +
      '</div>' +
      '<div style="width:34px; height:34px; border-radius:50%; background:rgba(251,248,242,0.7); display:flex; align-items:center; justify-content:center;">' +
        '<svg width="15" height="15" viewBox="0 0 15 15"><circle cx="2" cy="7.5" r="1.4" fill="oklch(0.4 0.02 75)"></circle><circle cx="7.5" cy="7.5" r="1.4" fill="oklch(0.4 0.02 75)"></circle><circle cx="13" cy="7.5" r="1.4" fill="oklch(0.4 0.02 75)"></circle></svg>' +
      '</div></div>';
  }

  function heroInner(lvl, dark) {
    if (dark) {
      return '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.22 0.014 75);">' +
        '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%;">' +
          '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.27 0.02 230)" stroke-width="20" fill="none"></path>' +
          '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.26 0.02 140)"></ellipse>' +
          '<ellipse cx="350" cy="370" rx="46" ry="34" fill="oklch(0.26 0.02 140)"></ellipse>' +
          segPaths(lvl.key, { dark: true }) +
          '<circle cx="220" cy="255" r="5.5" fill="oklch(0.78 0.12 55)"></circle>' +
          '<circle cx="220" cy="255" r="9" fill="none" stroke="oklch(0.78 0.12 55)" stroke-width="1.2" opacity="0.5"></circle>' +
          (lvl.sparkle ? '<circle class="sparkle-ring" cx="205" cy="150" r="7" fill="none" stroke="oklch(0.82 0.14 60)" stroke-width="1.6"></circle>' : '') +
        '</svg>' +
        mapChip(true) +
        (lvl.claimed ? claimedBadge(true) : '') +
        startWalkPill(true) +
      '</div>';
    }
    return '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
      '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%;">' +
        '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
        '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.90 0.02 140)"></ellipse>' +
        '<ellipse cx="350" cy="370" rx="46" ry="34" fill="oklch(0.90 0.02 140)"></ellipse>' +
        segPaths(lvl.key, { dark: false }) +
        '<circle cx="220" cy="255" r="5.5" fill="oklch(0.4 0.1 50)"></circle>' +
        '<circle cx="220" cy="255" r="9" fill="none" stroke="oklch(0.4 0.1 50)" stroke-width="1.2" opacity="0.5"></circle>' +
        (lvl.sparkle ? '<circle class="sparkle-ring" cx="205" cy="150" r="7" fill="none" stroke="oklch(0.6 0.13 55)" stroke-width="1.6"></circle>' : '') +
      '</svg>' +
      mapChip(false) +
      (lvl.claimed ? claimedBadge(false) : '') +
      startWalkPill(false) +
    '</div>';
  }

  function heroCard(lvl, dark) {
    var suffix = dark ? ' <span style="color:oklch(0.5 0.02 75); font-style:normal; font-size:13px;">· dark</span>' : '';
    return '<div>' +
      '<div style="margin-bottom:14px;">' +
        '<div style="font-family:\'Newsreader\',serif; font-style:italic; font-size:17px;">' + lvl.label + suffix + '</div>' +
        '<div style="font-size:12px; font-variant-numeric:tabular-nums; color:oklch(0.5 0.02 75); margin-top:2px;">' + lvl.percent + '% of Kreuzberg walked</div>' +
      '</div>' +
      frame({ width: 260, height: 562, dark: dark }, heroInner(lvl, dark)) +
    '</div>';
  }

  function fillingMap() {
    var cards = '';
    heroLevels.forEach(function (lvl) { cards += heroCard(lvl, false); });
    heroLevels.forEach(function (lvl) { cards += heroCard(lvl, true); });
    return sectionHead('The filling map',
        'The same street network, home area and viewpoint — three points in one person’s walking life, light and dark. An almost-empty map should feel like an invitation; a full one, like a keepsake.', '0 0 28px') +
      grid(cards);
  }

  // ── Notes & photos ─────────────────────────────────────────────────────────
  function noteMarkers() {
    var raw = [
      { x: 150, y: 195, isPhoto: true },
      { x: 275, y: 140, isPhoto: true },
      { x: 95,  y: 305, isPhoto: false },
      { x: 245, y: 255, isPhoto: true },
      { x: 325, y: 210, isPhoto: false }
    ];
    return raw.map(function (m) {
      var g = '<g><circle cx="' + m.x + '" cy="' + m.y + '" r="13" fill="oklch(0.97 0.01 80)" stroke="oklch(0.55 0.1 50)" stroke-width="1.4"></circle>';
      if (m.isPhoto) {
        g += '<rect x="' + (m.x - 6) + '" y="' + (m.y - 5) + '" width="12" height="9" rx="1.5" fill="none" stroke="oklch(0.5 0.09 50)" stroke-width="1.1"></rect>' +
             '<circle cx="' + m.x + '" cy="' + (m.y + 3) + '" r="2" fill="oklch(0.5 0.09 50)"></circle>';
      } else {
        g += '<line x1="' + (m.x - 5) + '" y1="' + (m.y - 2) + '" x2="' + (m.x + 5) + '" y2="' + (m.y - 2) + '" stroke="oklch(0.5 0.09 50)" stroke-width="1.3" stroke-linecap="round"></line>' +
             '<line x1="' + (m.x - 5) + '" y1="' + (m.y + 3) + '" x2="' + (m.x + 2) + '" y2="' + (m.y + 3) + '" stroke="oklch(0.5 0.09 50)" stroke-width="1.3" stroke-linecap="round"></line>';
      }
      return g + '</g>';
    }).join('');
  }

  function notesSection() {
    // A: browsing the memory layer
    var browse = card('Browsing memories', 'Streets ↔ memories toggle',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.90 0.02 140)"></ellipse>' +
            '<ellipse cx="350" cy="370" rx="46" ry="34" fill="oklch(0.90 0.02 140)"></ellipse>' +
            segPaths('year', { dark: false, opacity: 0.55 }) +
            noteMarkers() +
          '</svg>' +
          '<div style="position:absolute; top:16px; left:16px; right:16px; display:flex; justify-content:center;">' +
            '<div style="display:flex; background:rgba(251,248,242,0.9); border:1px solid rgba(58,46,34,0.1); border-radius:100px; padding:3px; gap:2px; box-shadow:0 4px 12px rgba(58,46,34,0.08);">' +
              '<div style="padding:6px 14px; font-size:11.5px; font-weight:500; color:oklch(0.5 0.02 75); border-radius:100px;">Streets</div>' +
              '<div style="padding:6px 14px; font-size:11.5px; font-weight:600; color:#FBF8F2; background:oklch(0.42 0.09 50); border-radius:100px;">Memories</div>' +
            '</div>' +
          '</div>' +
          '<div style="position:absolute; bottom:20px; right:16px;">' +
            '<div style="width:44px; height:44px; border-radius:50%; background:oklch(0.42 0.09 50); display:flex; align-items:center; justify-content:center; box-shadow:0 6px 16px rgba(58,46,34,0.25);">' +
              '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#FBF8F2" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"></path></svg>' +
            '</div>' +
          '</div>' +
        '</div>'));

    // B: note detail sheet
    var detail = card('Opening a note', 'Tapped a marker on the map',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%; opacity:0.5;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.90 0.02 140)"></ellipse>' +
            segPaths('year', { dark: false, opacity: 0.5 }) +
            '<circle cx="245" cy="255" r="15" fill="none" stroke="oklch(0.5 0.09 50)" stroke-width="1.6"></circle>' +
            '<circle cx="245" cy="255" r="6" fill="oklch(0.5 0.09 50)"></circle>' +
          '</svg>' +
          '<div style="position:absolute; left:0; right:0; bottom:0; top:34%; background:#FBF8F2; border-radius:22px 22px 0 0; box-shadow:0 -12px 30px rgba(58,46,34,0.18); padding:10px 20px 22px; display:flex; flex-direction:column;">' +
            '<div style="width:36px; height:4px; border-radius:3px; background:oklch(0.85 0.01 75); margin:0 auto 14px;"></div>' +
            '<div style="width:100%; height:110px; border-radius:12px; overflow:hidden; margin-bottom:14px; background:oklch(0.88 0.03 60); display:flex; align-items:center; justify-content:center;">' +
              '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="oklch(0.6 0.06 55)" stroke-width="1.6"><rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="8.5" cy="10" r="1.6" fill="oklch(0.6 0.06 55)" stroke="none"></circle><path d="M21 16l-5.5-5-4 4L8 12l-5 5"></path></svg>' +
            '</div>' +
            '<div style="display:flex; justify-content:space-between; align-items:baseline; margin-bottom:6px;">' +
              '<div style="font-family:\'Newsreader\',serif; font-size:15px; font-weight:500;">Görlitzer Park bench</div>' +
              '<div style="font-size:11px; color:oklch(0.55 0.02 75); font-variant-numeric:tabular-nums;">Oct 3, 2025</div>' +
            '</div>' +
            '<div style="font-size:13px; line-height:1.55; color:oklch(0.4 0.02 75); margin-bottom:14px;">The chestnut tree finally dropped its leaves. Sat here longer than planned.</div>' +
            '<div style="font-size:11.5px; font-weight:500; color:oklch(0.5 0.09 50); align-self:flex-start;">Edit note</div>' +
          '</div>' +
        '</div>'));

    // C: composing a new note
    var compose = card('Pinning a new one', 'From the + button or a long press',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%; opacity:0.45;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            segPaths('year', { dark: false, opacity: 0.5 }) +
            '<circle cx="245" cy="255" r="6" fill="oklch(0.5 0.09 50)"></circle>' +
          '</svg>' +
          '<div style="position:absolute; left:0; right:0; bottom:0; top:30%; background:#FBF8F2; border-radius:22px 22px 0 0; box-shadow:0 -12px 30px rgba(58,46,34,0.18); padding:16px 20px 22px; display:flex; flex-direction:column;">' +
            '<div style="width:36px; height:4px; border-radius:3px; background:oklch(0.85 0.01 75); margin:0 auto 14px;"></div>' +
            '<div style="font-family:\'Newsreader\',serif; font-size:16px; font-weight:500; margin-bottom:14px;">New note</div>' +
            '<div style="width:96px; height:96px; margin-bottom:14px; border-radius:10px; border:1.5px dashed oklch(0.75 0.03 60); display:flex; flex-direction:column; align-items:center; justify-content:center; gap:6px; color:oklch(0.55 0.05 55);">' +
              '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="oklch(0.55 0.05 55)" stroke-width="1.6"><rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="8.5" cy="10" r="1.6" fill="oklch(0.55 0.05 55)" stroke="none"></circle><path d="M21 16l-5.5-5-4 4L8 12l-5 5"></path></svg>' +
              '<span style="font-size:9.5px; font-weight:500;">Add a photo</span>' +
            '</div>' +
            '<div style="border:1px solid oklch(0.86 0.01 75); border-radius:10px; padding:10px 12px; font-size:12.5px; color:oklch(0.55 0.02 75); margin-bottom:12px;">What’s here?</div>' +
            '<div style="display:flex; align-items:center; gap:6px; font-size:11px; color:oklch(0.5 0.02 75); margin-bottom:18px;">' +
              '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="oklch(0.5 0.02 75)" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"></rect><path d="M16 2v4M8 2v4M3 10h18"></path></svg>' +
              '<span>Today · Jul 8, 2026 · stays on your phone</span>' +
            '</div>' +
            '<div style="align-self:flex-end; background:oklch(0.42 0.09 50); color:#FBF8F2; font-size:13px; font-weight:500; padding:10px 22px; border-radius:100px;">Save</div>' +
          '</div>' +
        '</div>'));

    return sectionHead('Notes &amp; photos — the memory layer',
        'Pinning a note or photo to a place, and browsing them back. This turns the heatmap into a life map — quiet markers, not pins from a delivery app.', '88px 0 28px') +
      grid(browse + detail + compose);
  }

  // ── Choosing a home area ───────────────────────────────────────────────────
  function gridLinesG(opacity) {
    return '<g opacity="' + opacity + '">' +
      '<line x1="60" y1="30" x2="60" y2="410" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="150" y1="30" x2="150" y2="410" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="240" y1="30" x2="240" y2="410" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="330" y1="30" x2="330" y2="410" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="30" y1="100" x2="410" y2="100" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="30" y1="190" x2="410" y2="190" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="30" y1="280" x2="410" y2="280" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
      '<line x1="30" y1="360" x2="410" y2="360" stroke="oklch(0.87 0.008 75)" stroke-width="1.2"></line>' +
    '</g>';
  }

  function suggestionRow(name, sub, active) {
    var rowBg = active ? ' background:oklch(0.93 0.02 65);' : '';
    var dotBg = active ? 'oklch(0.9 0.03 60)' : 'oklch(0.95 0.012 80)';
    var stroke = active ? 'oklch(0.45 0.09 50)' : 'oklch(0.5 0.02 75)';
    return '<div style="display:flex; align-items:center; gap:12px; padding:10px 6px; border-radius:10px;' + rowBg + '">' +
      '<div style="width:30px; height:30px; border-radius:50%; background:' + dotBg + '; display:flex; align-items:center; justify-content:center; flex-shrink:0;">' +
        '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="' + stroke + '" stroke-width="2"><path d="M12 21s7-6.3 7-12a7 7 0 1 0-14 0c0 5.7 7 12 7 12z"></path><circle cx="12" cy="9" r="2.4"></circle></svg>' +
      '</div>' +
      '<div>' +
        '<div style="font-family:\'Newsreader\',serif; font-size:14.5px; font-weight:500;">' + name + '</div>' +
        '<div style="font-size:11px; color:oklch(0.5 0.02 75);">' + sub + '</div>' +
      '</div>' +
    '</div>';
  }

  function onboardingSection() {
    // A: search / pick by name
    var search = card('Where do you want to fill in?', 'Search by city or district',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:#FBF8F2; padding:22px 20px; display:flex; flex-direction:column;">' +
          '<div style="font-family:\'Newsreader\',serif; font-size:19px; font-weight:500; line-height:1.3; margin-bottom:6px;">Where do you want to fill in?</div>' +
          '<div style="font-size:12px; color:oklch(0.5 0.02 75); margin-bottom:18px; line-height:1.5;">This becomes your main map. You can add travel areas later.</div>' +
          '<div style="display:flex; align-items:center; gap:8px; background:oklch(0.95 0.012 80); border:1px solid oklch(0.87 0.01 75); border-radius:11px; padding:10px 12px; margin-bottom:16px;">' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="oklch(0.5 0.02 75)" stroke-width="2"><circle cx="11" cy="11" r="7"></circle><path d="M21 21l-4.3-4.3"></path></svg>' +
            '<span style="font-size:12.5px; color:oklch(0.45 0.02 75);">Ber</span>' +
            '<span style="width:1px; height:13px; background:oklch(0.55 0.09 50); opacity:0.6;"></span>' +
          '</div>' +
          '<div style="font-size:10.5px; font-weight:600; letter-spacing:0.06em; text-transform:uppercase; color:oklch(0.6 0.02 75); margin-bottom:8px;">Suggestions</div>' +
          '<div style="display:flex; flex-direction:column; gap:2px; margin-bottom:auto;">' +
            suggestionRow('Berlin', 'Germany · admin boundary', true) +
            suggestionRow('Bremen', 'Germany · admin boundary', false) +
            suggestionRow('New York', 'United States · admin boundary', false) +
          '</div>' +
          '<div style="text-align:center; font-size:12px; font-weight:500; color:oklch(0.5 0.09 50); padding-top:14px;">Or draw an area on the map instead</div>' +
        '</div>'));

    // B: confirm boundary + size
    var confirm = card('Confirming the boundary', 'Before anything downloads',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" style="position:absolute; inset:0; width:100%; height:100%;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.90 0.02 140)"></ellipse>' +
            gridLinesG('0.5') +
            '<path d="M70,60 C160,30 300,45 380,110 C420,170 400,260 360,330 C300,400 180,410 110,370 C50,330 40,240 55,170 C60,120 55,85 70,60 Z" fill="oklch(0.85 0.05 60)" fill-opacity="0.32" stroke="oklch(0.5 0.09 50)" stroke-width="2" stroke-dasharray="6 5"></path>' +
          '</svg>' +
          '<div style="position:absolute; top:16px; left:16px; right:16px;">' +
            '<div style="background:rgba(251,248,242,0.9); backdrop-filter:blur(6px); border:1px solid rgba(58,46,34,0.1); border-radius:12px; padding:12px 16px;">' +
              '<div style="font-family:\'Newsreader\',serif; font-size:16px; font-weight:500;">Berlin</div>' +
              '<div style="font-size:11px; color:oklch(0.5 0.02 75); margin-top:1px;">Admin boundary · ~184 MB offline</div>' +
            '</div>' +
          '</div>' +
          '<div style="position:absolute; left:0; right:0; bottom:0; background:#FBF8F2; border-radius:22px 22px 0 0; box-shadow:0 -12px 30px rgba(58,46,34,0.15); padding:18px 20px 22px;">' +
            '<div style="font-size:12px; color:oklch(0.45 0.02 75); line-height:1.5; margin-bottom:14px;">Downloads once, works with no signal after. Nothing about where you walk ever leaves this phone.</div>' +
            '<div style="background:oklch(0.42 0.09 50); color:#FBF8F2; font-size:13px; font-weight:500; text-align:center; padding:12px; border-radius:100px;">Set as home area</div>' +
          '</div>' +
        '</div>'));

    // C: downloading state
    var downloading = card('Downloading, quietly', 'A calm wait, not a loading spinner',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:#FBF8F2; display:flex; flex-direction:column; align-items:center; justify-content:center; padding:0 34px; text-align:center;">' +
          '<svg width="72" height="72" viewBox="0 0 72 72" style="margin-bottom:22px;">' +
            '<circle cx="36" cy="36" r="30" fill="none" stroke="oklch(0.9 0.02 65)" stroke-width="4"></circle>' +
            '<circle cx="36" cy="36" r="30" fill="none" stroke="oklch(0.5 0.09 50)" stroke-width="4" stroke-linecap="round" stroke-dasharray="188.5" stroke-dashoffset="66" transform="rotate(-90 36 36)"></circle>' +
            '<text x="36" y="41" text-anchor="middle" font-family="Work Sans, sans-serif" font-size="15" font-weight="600" fill="oklch(0.3 0.03 60)">65%</text>' +
          '</svg>' +
          '<div style="font-family:\'Newsreader\',serif; font-size:17px; font-weight:500; margin-bottom:8px;">Filling in Berlin</div>' +
          '<div style="font-size:12.5px; color:oklch(0.5 0.02 75); line-height:1.55;">Building your offline map — streets, parks, water. Stays on your phone once it’s done.</div>' +
        '</div>'));

    // D: draw a rectangle instead
    var draw = card('Drawing your own area', 'For a district, not a whole city',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" style="position:absolute; inset:0; width:100%; height:100%;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="350" cy="90" rx="70" ry="42" fill="oklch(0.90 0.02 140)"></ellipse>' +
            gridLinesG('0.55') +
            '<rect x="95" y="130" width="230" height="200" fill="oklch(0.85 0.05 60)" fill-opacity="0.28" stroke="oklch(0.5 0.09 50)" stroke-width="2"></rect>' +
            '<circle cx="95" cy="130" r="7" fill="#FBF8F2" stroke="oklch(0.5 0.09 50)" stroke-width="2"></circle>' +
            '<circle cx="325" cy="130" r="7" fill="#FBF8F2" stroke="oklch(0.5 0.09 50)" stroke-width="2"></circle>' +
            '<circle cx="95" cy="330" r="7" fill="#FBF8F2" stroke="oklch(0.5 0.09 50)" stroke-width="2"></circle>' +
            '<circle cx="325" cy="330" r="7" fill="#FBF8F2" stroke="oklch(0.5 0.09 50)" stroke-width="9" stroke-opacity="0.18"></circle>' +
            '<circle cx="325" cy="330" r="7" fill="#FBF8F2" stroke="oklch(0.5 0.09 50)" stroke-width="2"></circle>' +
          '</svg>' +
          '<div style="position:absolute; top:16px; left:16px; right:16px; display:flex; justify-content:center;">' +
            '<div style="background:rgba(251,248,242,0.9); backdrop-filter:blur(6px); border-radius:100px; padding:8px 16px; font-size:11.5px; color:oklch(0.4 0.02 75);">Drag a corner to resize</div>' +
          '</div>' +
          '<div style="position:absolute; left:0; right:0; bottom:0; background:#FBF8F2; border-radius:22px 22px 0 0; box-shadow:0 -12px 30px rgba(58,46,34,0.15); padding:16px 20px 22px; display:flex; align-items:center; justify-content:space-between;">' +
            '<div>' +
              '<div style="font-family:\'Newsreader\',serif; font-size:15px; font-weight:500;">≈ 26 km²</div>' +
              '<div style="font-size:11px; color:oklch(0.5 0.02 75); margin-top:1px;">~40 MB offline</div>' +
            '</div>' +
            '<div style="background:oklch(0.42 0.09 50); color:#FBF8F2; font-size:12.5px; font-weight:500; padding:10px 20px; border-radius:100px;">Use this area</div>' +
          '</div>' +
        '</div>'));

    return sectionHead('Choosing a home area',
        'First run: pick a city or district by name, or draw your own boundary — then a compact offline map downloads for just that area. No account, no signal needed after.', '88px 0 28px') +
      grid(search + confirm + downloading + draw);
  }

  // ── Inviting an unwalked street ────────────────────────────────────────────
  function unwalkedSection() {
    // A: lock-screen notification
    var notif = card('A quiet notification', 'Arrives when you’re near it, not on a schedule',
      frame({ width: 260, height: 562, dark: true },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.2 0.025 55); display:flex; flex-direction:column; align-items:center;">' +
          '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%; opacity:0.16;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.5 0.05 60)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.4 0.05 140)"></ellipse>' +
            '<ellipse cx="350" cy="370" rx="46" ry="34" fill="oklch(0.4 0.05 140)"></ellipse>' +
          '</svg>' +
          '<div style="position:relative; text-align:center; margin-top:64px;">' +
            '<div style="font-family:\'Newsreader\',serif; font-weight:500; font-size:52px; color:#F2EDE3; line-height:1;">9:41</div>' +
            '<div style="font-size:12.5px; color:oklch(0.75 0.02 70); margin-top:6px;">Tuesday, October 14</div>' +
          '</div>' +
          '<div style="position:relative; margin-top:36px; width:calc(100% - 32px); background:rgba(251,248,242,0.94); backdrop-filter:blur(8px); border-radius:16px; padding:14px 16px; box-shadow:0 12px 30px rgba(0,0,0,0.3);">' +
            '<div style="display:flex; align-items:center; gap:9px; margin-bottom:8px;">' +
              '<div style="width:22px; height:22px; border-radius:6px; background:oklch(0.42 0.09 50); color:#FBF8F2; font-family:\'Newsreader\',serif; font-size:13px; font-weight:500; display:flex; align-items:center; justify-content:center; flex-shrink:0;">W</div>' +
              '<div style="font-size:11.5px; font-weight:600; color:oklch(0.4 0.02 75); flex:1;">Wanderlust</div>' +
              '<div style="font-size:10.5px; color:oklch(0.55 0.02 75);">now</div>' +
            '</div>' +
            '<div style="font-family:\'Newsreader\',serif; font-size:14.5px; font-weight:500; color:oklch(0.25 0.02 75); margin-bottom:4px;">Paul-Lincke-Ufer is one street over</div>' +
            '<div style="font-size:12px; line-height:1.5; color:oklch(0.42 0.02 75);">You’ve passed it forty times without setting foot on it.</div>' +
          '</div>' +
        '</div>'));

    // B: in-context hint on the map
    var hint = card('Noticing it on the map', 'Surfaces only when you’re already close by',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:oklch(0.95 0.012 80);">' +
          '<svg viewBox="0 0 440 440" preserveAspectRatio="xMidYMid slice" style="position:absolute; inset:0; width:100%; height:100%;">' +
            '<path d="M0,300 Q160,180 260,320 T440,250" stroke="oklch(0.90 0.014 220)" stroke-width="20" fill="none"></path>' +
            '<ellipse cx="110" cy="80" rx="80" ry="46" fill="oklch(0.90 0.02 140)"></ellipse>' +
            '<ellipse cx="350" cy="370" rx="46" ry="34" fill="oklch(0.90 0.02 140)"></ellipse>' +
            segPaths('month', { dark: false }) +
            '<circle cx="220" cy="255" r="5.5" fill="oklch(0.4 0.1 50)"></circle>' +
            '<path d="M220,255 C255,240 290,222 320,178" stroke="oklch(0.58 0.12 55)" stroke-width="3" stroke-linecap="round" stroke-dasharray="2 7" opacity="0.85"></path>' +
            '<circle class="sparkle-ring" cx="320" cy="178" r="7" fill="none" stroke="oklch(0.6 0.13 55)" stroke-width="1.6"></circle>' +
            '<circle cx="320" cy="178" r="3.4" fill="oklch(0.55 0.12 55)"></circle>' +
          '</svg>' +
          '<div style="position:absolute; top:16px; left:16px; right:16px; display:flex; justify-content:space-between; align-items:flex-start;">' +
            '<div style="background:rgba(251,248,242,0.86); backdrop-filter:blur(6px); border:1px solid rgba(58,46,34,0.1); border-radius:12px; padding:9px 14px;">' +
              '<div style="font-family:\'Newsreader\',serif; font-size:14px; font-weight:500; color:oklch(0.25 0.02 75);">Kreuzberg</div>' +
              '<div style="font-size:10.5px; color:oklch(0.5 0.02 75); margin-top:1px;">stays on your phone</div>' +
            '</div>' +
          '</div>' +
          '<div style="position:absolute; top:82px; left:16px; right:16px;">' +
            '<div style="display:flex; align-items:center; gap:10px; background:rgba(251,248,242,0.94); backdrop-filter:blur(6px); border:1px solid rgba(58,46,34,0.1); border-radius:12px; padding:10px 12px; box-shadow:0 8px 20px rgba(58,46,34,0.1);">' +
              '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="oklch(0.55 0.1 50)" stroke-width="2" style="flex-shrink:0;"><path d="M12 21s7-6.3 7-12a7 7 0 1 0-14 0c0 5.7 7 12 7 12z"></path><circle cx="12" cy="9" r="2.4"></circle></svg>' +
              '<div style="flex:1; min-width:0;">' +
                '<div style="font-family:\'Newsreader\',serif; font-size:12.5px; font-weight:500; color:oklch(0.25 0.02 75);">Paul-Lincke-Ufer</div>' +
                '<div style="font-size:10.5px; color:oklch(0.5 0.02 75);">240m away · never walked</div>' +
              '</div>' +
              '<div style="font-size:11px; font-weight:600; color:oklch(0.5 0.09 50); white-space:nowrap;">Preview</div>' +
            '</div>' +
          '</div>' +
          startWalkPill(false) +
        '</div>'));

    // C: browsable list
    var listRow = function (path, name, dist) {
      return '<div style="display:flex; align-items:center; gap:14px; padding:12px 4px; border-bottom:1px solid oklch(0.92 0.01 75);">' +
        '<svg width="34" height="34" viewBox="0 0 34 34" style="flex-shrink:0;"><path d="' + path + '" stroke="oklch(0.6 0.1 55)" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-dasharray="1.5 5"></path></svg>' +
        '<div style="flex:1;">' +
          '<div style="font-family:\'Newsreader\',serif; font-size:14.5px; font-weight:500;">' + name + '</div>' +
          '<div style="font-size:11px; color:oklch(0.5 0.02 75); margin-top:1px;">' + dist + '</div>' +
        '</div>' +
        '<span style="font-size:15px; color:oklch(0.6 0.02 75);">&#8250;</span>' +
      '</div>';
    };
    var lastRow = '<div style="display:flex; align-items:center; gap:14px; padding:12px 4px;">' +
      '<svg width="34" height="34" viewBox="0 0 34 34" style="flex-shrink:0;"><path d="M5,6 C8,16 18,14 20,24 C21,28 27,26 29,30" stroke="oklch(0.6 0.1 55)" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-dasharray="1.5 5"></path></svg>' +
      '<div style="flex:1;">' +
        '<div style="font-family:\'Newsreader\',serif; font-size:14.5px; font-weight:500;">G&#246;rlitzer Ufer path</div>' +
        '<div style="font-size:11px; color:oklch(0.5 0.02 75); margin-top:1px;">650m from home</div>' +
      '</div>' +
      '<span style="font-size:15px; color:oklch(0.6 0.02 75);">&#8250;</span>' +
    '</div>';
    var list = card('Browsing on purpose', 'A short list, ranked by distance from home',
      frame({ width: 260, height: 562, dark: false },
        '<div style="position:relative; height:100%; width:100%; overflow:hidden; background:#FBF8F2; padding:20px 20px 8px; display:flex; flex-direction:column; box-sizing:border-box;">' +
          '<div style="display:flex; align-items:center; gap:10px; margin-bottom:4px;">' +
            '<span style="font-size:15px; color:oklch(0.5 0.02 75);">&#8249;</span>' +
            '<div style="font-family:\'Newsreader\',serif; font-size:18px; font-weight:500;">Nearby, unwalked</div>' +
          '</div>' +
          '<div style="font-size:12px; color:oklch(0.5 0.02 75); margin:2px 0 18px; line-height:1.5;">Streets inside your home area you haven’t set foot on yet.</div>' +
          '<div style="display:flex; flex-direction:column; gap:4px;">' +
            listRow('M4,26 C10,20 12,12 22,8 C26,6 28,10 30,6', 'Paul-Lincke-Ufer', '240m from home') +
            listRow('M3,10 C12,8 16,18 26,16 C29,15.4 30,20 31,24', 'Wrangelstra&#223;e', '410m from home') +
            lastRow +
          '</div>' +
        '</div>'));

    return sectionHead('Inviting a walk you haven’t taken',
        'A nudge should feel like noticing, not a streak to protect. Three ways to point at a street nearby you’ve never walked — a quiet notification when you’re close, an in-context hint on the map itself, and a short list for when you’re in the mood to go find one on purpose. A new visual signifier: a soft dashed amber thread, distinct from the solid ink ramp, marking “known but unwalked.”', '88px 0 28px') +
      grid(notif + hint + list);
  }

  // ── layout helpers ─────────────────────────────────────────────────────────
  function sectionHead(title, sub, margin) {
    return '<div style="margin:' + margin + ';">' +
      '<div style="font-family:\'Newsreader\',serif; font-size:24px; font-weight:500; margin-bottom:6px;">' + title + '</div>' +
      '<div style="font-size:14px; color:oklch(0.5 0.02 75); max-width:660px;">' + sub + '</div>' +
    '</div>';
  }
  function grid(cards) {
    return '<div style="display:grid; grid-template-columns:repeat(3, 260px); gap:56px 44px; justify-content:start;">' + cards + '</div>';
  }
  function card(title, sub, body) {
    return '<div>' +
      '<div style="margin-bottom:14px;">' +
        '<div style="font-family:\'Newsreader\',serif; font-style:italic; font-size:17px;">' + title + '</div>' +
        '<div style="font-size:12px; color:oklch(0.5 0.02 75); margin-top:2px;">' + sub + '</div>' +
      '</div>' + body +
    '</div>';
  }

  function header() {
    return '<div style="margin-bottom:56px;">' +
      '<div style="font-size:12px; font-weight:600; letter-spacing:0.16em; color:oklch(0.5 0.06 50); text-transform:uppercase; margin-bottom:14px;">Wanderlust &nbsp;·&nbsp; Visual direction, v1</div>' +
      '<h1 style="font-family:\'Newsreader\',serif; font-weight:500; font-size:44px; line-height:1.15; margin:0 0 14px; max-width:640px;">A quiet map that fills in as you wander.</h1>' +
      '<p style="font-family:\'Newsreader\',serif; font-style:italic; font-size:19px; line-height:1.55; color:oklch(0.42 0.03 75); max-width:600px; margin:0;">Warm, single-hue ink accumulating on a calm paper map — never a dashboard, never a competition. This first pass establishes the colour ramp, type, and the signature moment: the filling map, at three stages of a life, in both light and dark.</p>' +
    '</div>';
  }

  function footer() {
    return '<div style="margin-top:56px; font-size:13px; color:oklch(0.5 0.02 75); max-width:640px; line-height:1.6;">' +
      'Next, once this direction lands: GPX import (“watch it fill instantly”) and the minimal recording state, built on this same foundation.' +
    '</div>';
  }

  function render() {
    var root = document.getElementById('canvas');
    root.innerHTML =
      header() +
      foundations() +
      fillingMap() +
      notesSection() +
      onboardingSection() +
      unwalkedSection() +
      footer();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', render);
  } else {
    render();
  }
})();
