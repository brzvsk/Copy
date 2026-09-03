// Copy marketing site, small progressive-enhancement behaviors.
// No analytics, no network calls, no external libraries.
(function () {
  "use strict";

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

  // Selection travel: slowly move the highlighted card across the hero shelf so it reads
  // like someone browsing their clipboard, not a frozen mock. Pauses when the tab is
  // hidden or the pointer is inspecting the shelf; disabled under reduced motion.
  var scene = document.querySelector(".hero-visual .scene");
  var cards = scene ? Array.prototype.slice.call(scene.querySelectorAll(".card")) : [];
  if (scene && cards.length > 1 && !reduce) {
    var current = cards.findIndex(function (c) { return c.classList.contains("sel"); });
    if (current < 0) { current = 0; }
    var timer = null;
    var advance = function () {
      cards[current].classList.remove("sel");
      current = (current + 1) % cards.length;
      cards[current].classList.add("sel");
    };
    var start = function () { if (!timer) { timer = window.setInterval(advance, 2400); } };
    var stop = function () { if (timer) { window.clearInterval(timer); timer = null; } };
    document.addEventListener("visibilitychange", function () {
      if (document.hidden) { stop(); } else { start(); }
    });
    scene.addEventListener("pointerenter", stop);
    scene.addEventListener("pointerleave", start);
    window.setTimeout(start, 1700);   // let the load-in settle first
  }
})();
