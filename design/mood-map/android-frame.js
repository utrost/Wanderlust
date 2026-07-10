// Simplified Android (Material 3) device frame — status bar + content +
// gesture nav. No dependencies, no image assets. Ported from the Claude Design
// handoff bundle (android-frame.jsx) into a plain string-returning helper so it
// can wrap arbitrary screen markup without React.
//
// Usage:  androidFrame({ width, height, dark }, innerHTML) -> HTML string
(function (global) {
  'use strict';

  var MD = {
    surface: '#f4fbf8',
    onSurface: '#171d1b',
    frameBorder: 'rgba(116,119,117,0.5)'
  };

  function statusBar(dark) {
    var c = dark ? '#fff' : MD.onSurface;
    return '' +
      '<div style="height:40px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;position:relative;font-family:Roboto,system-ui,sans-serif;">' +
        '<div style="width:128px;display:flex;align-items:center;gap:8px;">' +
          '<span style="font-size:14px;font-weight:400;letter-spacing:0.25px;line-height:20px;color:' + c + ';">9:30</span>' +
        '</div>' +
        '<div style="position:absolute;left:50%;top:8px;transform:translateX(-50%);width:24px;height:24px;border-radius:100px;background:#2e2e2e;"></div>' +
        '<div style="display:flex;align-items:center;">' +
          '<div style="display:flex;padding-right:2px;">' +
            '<svg width="16" height="16" viewBox="0 0 16 16" style="margin-right:-2px;"><path d="M8 13.3L.67 5.97a10.37 10.37 0 0114.66 0L8 13.3z" fill="' + c + '"/></svg>' +
            '<svg width="16" height="16" viewBox="0 0 16 16" style="margin-right:-2px;"><path d="M14.67 14.67V1.33L1.33 14.67h13.34z" fill="' + c + '"/></svg>' +
          '</div>' +
          '<svg width="16" height="16" viewBox="0 0 16 16"><rect x="3.75" y="2" width="8.5" height="13" rx="1.5" fill="' + c + '"/><rect x="5.5" y="0.9" width="5" height="2" rx="0.5" fill="' + c + '"/></svg>' +
        '</div>' +
      '</div>';
  }

  function navBar(dark) {
    return '' +
      '<div style="height:24px;display:flex;align-items:center;justify-content:center;">' +
        '<div style="width:108px;height:4px;border-radius:2px;background:' + (dark ? '#fff' : MD.onSurface) + ';opacity:0.4;"></div>' +
      '</div>';
  }

  function androidFrame(opts, inner) {
    opts = opts || {};
    var width = opts.width || 260;
    var height = opts.height || 562;
    var dark = !!opts.dark;
    return '' +
      '<div style="width:' + width + 'px;height:' + height + 'px;border-radius:18px;overflow:hidden;' +
        'background:' + (dark ? '#1d1b20' : MD.surface) + ';border:8px solid ' + MD.frameBorder + ';' +
        'box-shadow:0 30px 80px rgba(0,0,0,0.25);display:flex;flex-direction:column;box-sizing:border-box;">' +
        statusBar(dark) +
        '<div style="flex:1;overflow:auto;">' + inner + '</div>' +
        navBar(dark) +
      '</div>';
  }

  global.androidFrame = androidFrame;
})(window);
