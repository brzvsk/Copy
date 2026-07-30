// Copy marketing site, small progressive-enhancement behaviors.
// No analytics, no network calls, no external libraries.
(function () {
  "use strict";

  // Copy-to-clipboard for the Homebrew command chips.
  document.querySelectorAll("[data-copy]").forEach(function (button) {
    var defaultLabel = button.textContent;
    button.addEventListener("click", function () {
      var text = button.getAttribute("data-copy");
      var done = function () {
        button.textContent = "Copied";
        button.classList.add("is-copied");
        window.setTimeout(function () {
          button.textContent = defaultLabel;
          button.classList.remove("is-copied");
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text); done(); });
      } else {
        fallbackCopy(text);
        done();
      }
    });
  });

  // Cursor parallax: the hero shelf mock tilts toward the pointer.
  var tilt = document.querySelector("[data-tilt]");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (tilt && !reduce) {
    var shelf = tilt.querySelector(".shelf");
    tilt.addEventListener("pointermove", function (e) {
      var r = tilt.getBoundingClientRect();
      var px = ((e.clientX - r.left) / r.width - 0.5) * 2;   // -1 .. 1
      var py = ((e.clientY - r.top) / r.height - 0.5) * 2;
      shelf.style.setProperty("--px", px.toFixed(3));
      shelf.style.setProperty("--py", py.toFixed(3));
    });
    tilt.addEventListener("pointerleave", function () {
      shelf.style.setProperty("--px", "0");
      shelf.style.setProperty("--py", "0");
    });
  }

  function fallbackCopy(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "absolute";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    try { document.execCommand("copy"); } catch (err) { /* no-op */ }
    document.body.removeChild(area);
  }
})();
