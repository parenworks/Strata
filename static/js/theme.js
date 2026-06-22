/* Strata theme switcher - runs before body paint to avoid flash */
(function () {
  var stored = localStorage.getItem('strata-theme') || 'light';
  document.documentElement.setAttribute('data-theme', stored);

  window.strataToggleTheme = function () {
    var current = document.documentElement.getAttribute('data-theme') || 'light';
    var next = current === 'light' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('strata-theme', next);
    var btn = document.getElementById('theme-toggle-btn');
    if (btn) btn.textContent = next === 'dark' ? '☀ Light mode' : '◑ Dark mode';
  };
})();
